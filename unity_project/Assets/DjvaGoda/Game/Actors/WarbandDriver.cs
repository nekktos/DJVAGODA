// Отряд стороны под ИИ (перенос ai/warband.gd): мозг ядра решает набег,
// оборону и отход, бойцы получают якорь, разворот и строй — ровно то, что
// дал бы живой командир. Считает только хост.
using System.Collections.Generic;
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public class WarbandDriver : MonoBehaviour
    {
        public Faction Side;
        public NavWorld Nav;
        public readonly List<UnitAgent> Band = new List<UnitAgent>();
        WarbandBrain _brain;
        public WarbandBrain Brain { get { return _brain; } }

        /// Мозг заводится в Start: сторону назначают после AddComponent.
        void Start() { _brain = new WarbandBrain(Side); }

        void Update()
        {
            if (_brain == null) return;
            Band.RemoveAll(unit => unit == null || !unit.Alive);
            var view = new WarbandView();
            foreach (var unit in Band) view.Band.Add(unit.At);
            var goals = MatchGoals.Instance;
            if (Side == Faction.Villain && goals != null && goals.State.PalaceOwner != Faction.Villain && !MatchGoals.IsOut(Side))
                view.Palace = MatchState.Palace;
            foreach (var actor in Actor.All)
            {
                if (actor == null || !actor.Alive) continue;
                if (actor is BuildingActor)
                {
                    view.Buildings.Add(new SidedPoint(actor.At, actor.Side));
                    if (actor.Side == (int)Side)
                    {
                        view.Posts.Add(actor.At);
                        var kind = ((BuildingActor)actor).State.Kind;
                        if (kind == BuildingKind.SwordBarracks || kind == BuildingKind.ArcherBarracks) view.HasBarracks = true;
                    }
                }
                else if (actor is CaravanActor)
                {
                    var cart = (CaravanActor)actor;
                    view.Carts.Add(new CartSighting { Id = cart.Id, At = cart.At, Side = cart.Side, Speed = cart.Trip.SpeedNow, Ahead = cart.Trip.PathAhead() });
                }
                else
                {
                    view.Fighters.Add(new SidedPoint(actor.At, actor.Side));
                    if (actor is PlayerCharacter && actor.Side == (int)Side && ((PlayerCharacter)actor).LocalControl) view.HumanOnSide = true;
                }
            }
            var order = _brain.Tick(Time.deltaTime, view, Nav != null && Nav.Ready ? Nav.Finder : null);
            if (!order.HasValue) return;
            foreach (var unit in Band)
            {
                unit.Brain.AiLed = true;
                unit.Brain.AiAnchor = order.Value.Anchor;
                unit.Brain.AiYaw = order.Value.Yaw;
                unit.Brain.AiFormation = order.Value.Formation;
                unit.Brain.Leash = order.Value.Leash;
            }
        }
    }
}
