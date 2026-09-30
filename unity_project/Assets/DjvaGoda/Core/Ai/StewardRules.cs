// Решения распорядителя ИИ — чистыми функциями (перенос steward.gd).
//
// ИИ хозяйствует ТЕМ ЖЕ набором правил, что игрок: те же цены, та же казна,
// тот же наём. Здесь — только решения «что строить, кого куда поставить, за
// чем слать обоз»; исполнение (спавн, пути, проверка места) — Unity-слой.
// Каждое решение выверено «долгими партиями» Godot-версии — см. её комментарии
// в godot_project/scripts/ai/steward.gd.
using System;
using System.Collections.Generic;

namespace DjvaGoda.Core
{
    public enum LabourerRole { Lumberjack, Miner, Militia, Builder, Farmer }

    /// Что распорядитель знает о своей стороне в этот такт.
    public struct EconomyView
    {
        public int Crew;
        public bool Constructing;
        public int FieldsReady;
        public int FieldsAll;
        public bool CaravanAtMine;
        public bool OreNearby;
        public bool ForgeReady;
        public int Horses;
        /// Какие постройки у стороны есть (любой готовности).
        public HashSet<BuildingKind> Has;
    }

    public static class StewardRules
    {
        /// Склад, конюшня (путь к первому обозу), поле, дальше развитие; кузня
        /// последней. Конюшня раньше поля: иначе снесённое поле съедало камень
        /// микро-шахты, и на конюшню не оставалось («долгая партия»).
        public static readonly BuildingKind[] BuildOrder =
        {
            BuildingKind.Storage, BuildingKind.Stable, BuildingKind.Farm, BuildingKind.House,
            BuildingKind.SwordBarracks, BuildingKind.ArcherBarracks, BuildingKind.Forge,
        };

        public static readonly BuildingKind[] FortifyOrder =
        {
            BuildingKind.Storage, BuildingKind.Stable, BuildingKind.SwordBarracks,
            BuildingKind.ArcherBarracks, BuildingKind.House, BuildingKind.Forge,
        };

        public const int CrewBeforeHorse = 2;
        public const int HorsesWanted = 4;
        public const int AiHarness = 3;
        public const int BuildersWanted = 2;
        public const int SquadWanted = 6;
        public const int CaravansWanted = 1;
        public const int GuardsPerCaravan = 2;
        public const int WorkersKept = 2;
        public const int MinersAtMine = 2;
        public const int MouthsPerField = 5;
        public const float OreRange = 150f;

        /// Что строить следующим; null — построено всё. Сверх очереди — ещё
        /// поле, когда ртов больше, чем поля прокормят (только если одно уже есть).
        public static BuildingKind? NextBuilding(EconomyView view)
        {
            if (view.FieldsAll > 0 && view.FieldsAll * MouthsPerField < view.Crew) return BuildingKind.Farm;
            foreach (var kind in BuildOrder)
                if (view.Has == null || !view.Has.Contains(kind)) return kind;
            return null;
        }

        /// Нанять ли ещё батрака. Пока нет лошади — не больше двоих: золото
        /// микро-шахты — это двое батраков и лошадь, а без лошади нет обоза.
        public static bool ShouldHire(EconomyView view)
        {
            if (view.Crew >= Res.LabourerLimit) return false;
            if (view.Horses <= 0 && view.Crew >= CrewBeforeHorse) return false;
            return true;
        }

        /// Сколько кого нужно: стройка, поле, шахта обоза, лес.
        public static int[] AssignRoles(EconomyView view, int[] nextCost, IStock have)
        {
            var wanted = new int[Enum.GetValues(typeof(LabourerRole)).Length];
            if (view.Crew <= 0) return wanted;
            if (view.Constructing) wanted[(int)LabourerRole.Builder] = Math.Min(BuildersWanted, view.Crew);
            int rest = view.Crew - wanted[(int)LabourerRole.Builder];
            if (rest > 0)
            {
                wanted[(int)LabourerRole.Farmer] = Math.Min(view.FieldsReady, rest);
                rest -= wanted[(int)LabourerRole.Farmer];
            }
            if (rest <= 0) return wanted;

            bool needStone = nextCost != null && have != null && (
                have.GetAmount(ResourceKind.Stone) < Res.At(nextCost, ResourceKind.Stone)
                || have.GetAmount(ResourceKind.Iron) < Res.At(nextCost, ResourceKind.Iron));

            if (view.CaravanAtMine)
            {
                // Обоз у шахты — двое копают там: обоз важнее носки руками.
                wanted[(int)LabourerRole.Miner] = Math.Min(MinersAtMine, rest);
                wanted[(int)LabourerRole.Lumberjack] = rest - wanted[(int)LabourerRole.Miner];
            }
            else if (!view.OreNearby)
            {
                // Копать рядом нечего — за камнем на перекрёсток пешком не ходим.
                wanted[(int)LabourerRole.Lumberjack] = rest;
            }
            else if (needStone)
            {
                wanted[(int)LabourerRole.Miner] = rest - rest / 2;
                wanted[(int)LabourerRole.Lumberjack] = rest / 2;
            }
            else
            {
                wanted[(int)LabourerRole.Lumberjack] = rest - rest / 2;
                wanted[(int)LabourerRole.Miner] = rest / 2;
            }
            return wanted;
        }

        /// За какой рудой слать обоз: за той, которой меньше всего. Железо,
        /// камень, золото; с кузней — и уголь. Равенство — в пользу железа.
        public static ResourceKind PickOre(IStock have, bool forgeReady)
        {
            var wanted = new List<ResourceKind> { ResourceKind.Iron, ResourceKind.Stone, ResourceKind.Gold };
            if (forgeReady) wanted.Add(ResourceKind.Coal);
            var best = ResourceKind.Iron;
            int bestHave = int.MaxValue;
            foreach (var kind in wanted)
            {
                int amount = have != null ? have.GetAmount(kind) : 0;
                if (amount < bestHave)
                {
                    bestHave = amount;
                    best = kind;
                }
            }
            return best;
        }

        /// Сколько батраков отдать в охрану обоза: двое, но так, чтобы двое
        /// остались работать.
        public static int CaravanGuards(int crew)
        {
            return Math.Max(0, Math.Min(GuardsPerCaravan, crew - WorkersKept));
        }

        public const float ThinkInterval = 4f;
        /// Где искать место под постройку: кольца вокруг точки стороны, ближнее первым.
        public static readonly float[] SpotRadii = { 26f, 38f, 52f, 68f, 86f, 106f, 128f };
        public const int SpotAngles = 12;

        /// Место под постройку: первое пригодное на кольцах вокруг базы; null — тесно.
        public static V3? FindSpot(V3 home, Func<V3, bool> buildable)
        {
            foreach (float radius in SpotRadii)
                for (int i = 0; i < SpotAngles; i++)
                {
                    double angle = 2.0 * Math.PI * i / SpotAngles;
                    var point = new V3(home.X + (float)Math.Cos(angle) * radius, 0f, home.Z + (float)Math.Sin(angle) * radius);
                    if (buildable == null || buildable(point)) return point;
                }
            return null;
        }

        /// Куда ставить нового батрака: по спирали от точки стороны.
        public static V3 HireSpot(V3 home, int crew)
        {
            float angle = crew * 0.9f, radius = 5f + crew;
            return home + new V3((float)Math.Cos(angle) * radius, 0.5f, (float)Math.Sin(angle) * radius);
        }

        /// Кого снять с роли, чтобы добрать нехватку: у кого больше всего лишних; −1 — лишних нет.
        public static int DonorRole(int[] have, int[] wanted)
        {
            int best = -1, surplus = 0;
            for (int role = 0; role < have.Length; role++)
            {
                int extra = have[role] - wanted[role];
                if (extra > surplus)
                {
                    surplus = extra;
                    best = role;
                }
            }
            return best;
        }

        /// Перестановки ролей: (с какой, на какую), по одному батраку, пока нехватка
        /// покрывается лишними. Новых не нанимает — только переводит.
        public static List<KeyValuePair<LabourerRole, LabourerRole>> RoleMoves(int[] have, int[] wanted)
        {
            var moves = new List<KeyValuePair<LabourerRole, LabourerRole>>();
            var now = (int[])have.Clone();
            for (int role = 0; role < now.Length; role++)
                while (now[role] < wanted[role])
                {
                    int donor = DonorRole(now, wanted);
                    if (donor < 0) return moves;
                    now[donor]--;
                    now[role]++;
                    moves.Add(new KeyValuePair<LabourerRole, LabourerRole>((LabourerRole)donor, (LabourerRole)role));
                }
            return moves;
        }

        /// Докупить лошадь: конюшня есть, лошадей меньше четырёх.
        public static bool WantHorse(bool stableReady, int horses) { return stableReady && horses < HorsesWanted; }

        /// Кого набрать в отряд: лучника, если есть их казарма, иначе мечника; null — казарм нет
        /// или отряд полон.
        public static UnitKind? TrainKind(bool archerBarracks, bool swordBarracks, int band, int capacity)
        {
            if (band >= Math.Min(SquadWanted, capacity)) return null;
            if (archerBarracks) return UnitKind.Archer;
            if (swordBarracks) return UnitKind.Swordsman;
            return null;
        }

        /// Новобранец встаёт по кругу в 8 м от точки стороны.
        public static V3 TrainSpot(V3 home, int slot)
        {
            float angle = slot * 0.9f;
            return home + new V3((float)Math.Cos(angle) * 8f, 0.5f, (float)Math.Sin(angle) * 8f);
        }

        /// Ещё склад: обоз ждёт у полного склада, новый склад не строится, и он по карману.
        public static bool NeedExtraStorage(bool cartWaiting, bool storageUnderConstruction, bool affordable)
        {
            return cartWaiting && !storageUnderConstruction && affordable;
        }

        /// Хватает ли на укрепление, не съедая следующую постройку.
        public static bool CanFortify(int[] upgradeCost, int[] nextBuildingCost, IStock have)
        {
            if (upgradeCost == null || upgradeCost.Length == 0 || have == null) return false;
            var need = Res.Fit(upgradeCost);
            var build = Res.Fit(nextBuildingCost);
            for (int i = 0; i < Res.Count; i++)
                if (have.GetAmount((ResourceKind)i) < need[i] + build[i]) return false;
            return true;
        }
    }
}
