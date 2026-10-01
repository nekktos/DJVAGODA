// Распорядитель хозяйства стороны под ИИ (перенос ai/steward.gd): раз в
// четыре секунды нанимает, строит, укрепляет, расставляет роли, набирает
// отряд, покупает лошадей, шлёт обоз к шахте с охраной и строит лишний
// склад, когда обоз ждёт у полного. Решения — StewardRules ядра; здесь — руки.
// Стратегию не трогаем (решение автора): порядок и числа — как в Godot-версии.
//
// ЕЩЁ НЕ ПЕРЕНЕСЕНО сюда (правила в ядре есть): укрепление ступенями
// (StewardRules.CanFortify), лишний склад у полного (NeedExtraStorage),
// охрана обоза батраками (CaravanGuards), «руда рядом» (сейчас всегда да),
// погрузка у шахты (Load = null — обоз едет пустым). Доделать вместе с
// шахтами в Unity-слое.
using System.Collections.Generic;
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public class StewardDriver : MonoBehaviour
    {
        public Faction Side = Faction.Villain;
        public Wallet Treasury;
        public NavWorld Nav;
        public World World;
        public WarbandDriver Warband;
        public readonly List<LabourerAgent> Crew = new List<LabourerAgent>();
        float _think;

        V3 Home { get { return Factions.Spawn[(int)Side]; } }

        void Update()
        {
            if (Treasury == null) return;
            _think += Time.deltaTime;
            if (_think < StewardRules.ThinkInterval) return;
            _think = 0f;
            Crew.RemoveAll(worker => worker == null || !worker.Alive);
            var view = View();
            Hire(view);
            Build(view);
            AssignRoles(view);
            Train();
            BuyHorse();
            SendCaravan();
        }

        List<BuildingActor> Buildings()
        {
            var list = new List<BuildingActor>();
            foreach (var actor in Actor.All)
            {
                var building = actor as BuildingActor;
                if (building != null && building.Alive && building.Side == (int)Side) list.Add(building);
            }
            return list;
        }

        BuildingActor Ready(BuildingKind kind)
        {
            foreach (var building in Buildings())
                if (building.State.Kind == kind && building.State.Done) return building;
            return null;
        }

        EconomyView View()
        {
            var view = new EconomyView { Crew = Crew.Count, Has = new HashSet<BuildingKind>(), Horses = Treasury.Horses };
            foreach (var building in Buildings())
            {
                view.Has.Add(building.State.Kind);
                if (!building.State.Done) view.Constructing = true;
                if (building.State.Kind == BuildingKind.Farm)
                {
                    view.FieldsAll++;
                    if (building.State.Done) view.FieldsReady++;
                }
                if (building.State.Kind == BuildingKind.Forge && building.State.Done) view.ForgeReady = true;
            }
            foreach (var actor in Actor.All)
            {
                var cart = actor as CaravanActor;
                if (cart != null && cart.Side == (int)Side && cart.Trip.State == CaravanState.Loading) view.CaravanAtMine = true;
            }
            view.OreNearby = true;
            return view;
        }

        void Hire(EconomyView view)
        {
            if (!StewardRules.ShouldHire(view) || !Treasury.Spend(Res.LabourerCost)) return;
            var at = StewardRules.HireSpot(Home, Crew.Count);
            var go = GameObject.CreatePrimitive(PrimitiveType.Capsule);
            go.name = "Батрак";
            Destroy(go.GetComponent<CapsuleCollider>());
            go.transform.position = at.ToUnity();
            var worker = go.AddComponent<LabourerAgent>();
            worker.Brain = new LabourerBrain(Side, LabourerRole.Lumberjack);
            worker.Home = Home;
            worker.Nav = Nav;
            worker.World = World;
            worker.Treasury = Treasury;
            Crew.Add(worker);
        }

        void Build(EconomyView view)
        {
            if (view.Constructing) return;
            var kind = StewardRules.NextBuilding(view);
            if (!kind.HasValue || !Treasury.CanAfford(Res.BuildingCost(kind.Value))) return;
            var standing = new List<KeyValuePair<BuildingKind, V3>>();
            foreach (var actor in Actor.All)
            {
                var building = actor as BuildingActor;
                if (building != null && building.Alive) standing.Add(new KeyValuePair<BuildingKind, V3>(building.State.Kind, building.At));
            }
            var spot = StewardRules.FindSpot(Home, point => World == null || Placement.Buildable(point, kind.Value, World.Relief, standing));
            if (!spot.HasValue || !Treasury.Spend(Res.BuildingCost(kind.Value))) return;
            BuildingActor.Spawn(kind.Value, Side, spot.Value, false, Nav);
        }

        void AssignRoles(EconomyView view)
        {
            var next = StewardRules.NextBuilding(view);
            var wanted = StewardRules.AssignRoles(view, next.HasValue ? Res.BuildingCost(next.Value) : null, Treasury);
            var have = new int[wanted.Length];
            foreach (var worker in Crew) have[(int)worker.Brain.Role]++;
            foreach (var move in StewardRules.RoleMoves(have, wanted))
                foreach (var worker in Crew)
                    if (worker.Brain.Role == move.Key)
                    {
                        worker.Brain.SetRole(move.Value);
                        break;
                    }
        }

        void Train()
        {
            if (Warband == null) return;
            int houses = 0;
            foreach (var building in Buildings())
                if (building.State.Kind == BuildingKind.House && building.State.Done) houses++;
            int capacity = Mathf.Min(Res.SquadLimit, Res.SquadBase + houses * Res.HouseSlots);
            var kind = StewardRules.TrainKind(Ready(BuildingKind.ArcherBarracks) != null, Ready(BuildingKind.SwordBarracks) != null,
                Warband.Band.Count, capacity);
            if (!kind.HasValue) return;
            if (!Treasury.Spend(kind.Value == UnitKind.Archer ? Res.ArcherCost : Res.UnitCost)) return;
            int slot = Warband.Band.Count;
            var go = GameObject.CreatePrimitive(PrimitiveType.Capsule);
            go.name = kind.Value == UnitKind.Archer ? "Лучник" : "Мечник";
            Destroy(go.GetComponent<CapsuleCollider>());
            go.transform.position = StewardRules.TrainSpot(Home, slot).ToUnity();
            var unit = go.AddComponent<UnitAgent>();
            unit.Setup(kind.Value, (int)Side, slot, Home, AiStats.GarrisonLeash);
            unit.Nav = Nav;
            Warband.Band.Add(unit);
        }

        void BuyHorse()
        {
            if (!StewardRules.WantHorse(Ready(BuildingKind.Stable) != null, Treasury.Horses)) return;
            if (Treasury.Spend(Res.HorseCost)) Treasury.Horses++;
        }

        void SendCaravan()
        {
            var storage = Ready(BuildingKind.Storage);
            if (storage == null) return;
            int out_ = 0;
            foreach (var actor in Actor.All)
                if (actor is CaravanActor && actor.Side == (int)Side) out_++;
            if (out_ >= StewardRules.CaravansWanted) return;
            int free = Treasury.HorsesFree;
            if (free <= 0) return;
            var ore = StewardRules.PickOre(Treasury, Ready(BuildingKind.Forge) != null);
            var mine = MapLayout.MineOf(ore);
            if (!mine.HasValue) return;
            int team = Mathf.Min(StewardRules.AiHarness, free);
            Treasury.HorsesOut += team;
            var route = new List<V3> { storage.At, MapLayout.MineEntrance(mine.Value.At) };
            if (Nav != null && Nav.Ready)
            {
                var walked = Nav.PathBetween(storage.At, MapLayout.MineEntrance(mine.Value.At));
                if (walked.Count >= 2) route = walked;
            }
            CaravanActor.Spawn(Side, 0, route, team, World, Treasury, null);
        }
    }
}
