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
