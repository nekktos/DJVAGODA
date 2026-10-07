// Личный отряд игрока (перенос player.gd: request_train_unit, request_formation,
// request_squad_move, request_squad_follow, request_escort_caravan).
//
// Нанимают У СВОЕЙ КАЗАРМЫ (мечника — у казармы мечников, лучника — у
// лучников): наём — дело в конкретном месте, а не галочка «построено».
// Вместимость — от построек: база плюс дом дружины (Deals.SquadCapacity).
// Отряд идёт за командиром в выбранном строю; приказ «туда» (ПКМ сверху)
// ставит его на точку лицом по маршу; «ко мне» (G) — снова за командиром;
// «с обозом» (H) — к ближайшей своей повозке: охрана — выбор между «войско
// бьёт» и «войско бережёт груз», бесплатной она не бывает. Строи — F2–F5.
//
// Считает хост; владельцу — сводка (NetPlayer.Squad).
using System.Collections.Generic;
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public static class Squads
    {
        /// Бойцы игрока (у хоста): нанятые, не призванные звери.
        public static List<UnitAgent> Of(PlayerCharacter player)
        {
            var list = new List<UnitAgent>();
            foreach (var actor in Actor.All)
            {
                var unit = actor as UnitAgent;
                if (unit != null && unit.Alive && unit.Commander == player && unit.Lifetime <= 0f) list.Add(unit);
            }
            return list;
        }

        public static int Capacity(Faction side)
        {
            int houses = 0;
            foreach (var actor in Actor.All)
            {
                var building = actor as BuildingActor;
                if (building != null && building.Alive && building.State.Done && building.Side == (int)side
                    && building.State.Kind == BuildingKind.House) houses++;
            }
            return Deals.SquadCapacity(houses);
        }

        /// Нанять бойца у казармы (у хоста). Отказ — причиной на экран.
        public static Deal Train(PlayerCharacter player, bool archer, BuildingActor atBarracks, bool hasBarracks)
        {
            var squad = Of(player);
            var deal = Deals.TrainUnit(Treasury.Of(player.Faction), archer, atBarracks != null, hasBarracks, squad.Count, Capacity(player.Faction));
            if (!deal.Ok) return deal;
            // Перед фасадом с учётом поворота казармы: «+9 м по z от центра»
            // у повёрнутой казармы стражи попадало в стены, и боец застревал
            // в её коробке (playtest-10: «отряд растёт, а толку нет»).
            var size = Res.BuildingSize(atBarracks.State.Kind);
            float yaw = atBarracks.transform.eulerAngles.y * Mathf.Deg2Rad;
            var front = atBarracks.At + UnitBrain.Rotate(new V3(0f, 0f, size.Z * 0.5f + 4f), yaw);
            Spawn(player, archer ? UnitKind.Archer : UnitKind.Swordsman, front, squad.Count);
            return deal;
        }

        /// Боец за командиром (наём и восстановление из сохранения). Разводим
        /// по спирали: в одной точке капсулы влезают друг в друга.
        public static UnitAgent Spawn(PlayerCharacter player, UnitKind kind, V3 near, int index)
        {
            float angle = index * 0.9f;
            float radius = 3f + index * 0.45f;
            var at = near + new V3(Mathf.Cos(angle) * radius, 1f, Mathf.Sin(angle) * radius);
            var role = kind == UnitKind.Archer ? AgentRole.Archer : AgentRole.Swordsman;
            var go = Agents.Make(role, player.Faction, at, kind == UnitKind.Archer ? "Лучник отряда" : "Мечник отряда");
            var unit = go.AddComponent<UnitAgent>();
            unit.Setup(kind, (int)player.Faction, index, at, UnitStats.SquadLeash);
            unit.Commander = player;
            unit.CommanderFormation = player.SquadFormation;
            unit.Nav = Object.FindAnyObjectByType<NavWorld>();
            Agents.Show(go);
            return unit;
        }

        public static void SetFormation(PlayerCharacter player, FormationKind formation)
        {
            player.SquadFormation = formation;
            foreach (var unit in Of(player)) unit.CommanderFormation = formation;
        }

        /// Отряд — на точку, лицом по направлению марша.
        public static void Move(PlayerCharacter player, V3 point)
        {
            if (Mathf.Abs(point.X) > Deals.RouteBound || Mathf.Abs(point.Z) > Deals.RouteBound) return;
            var march = (point - Anchor(player)).Flat();
            player.SquadRally = point;
            if (march.Length() > 0.5f) player.SquadRallyYaw = Mathf.Atan2(march.X, march.Z);
            player.SquadHold = true;
            foreach (var unit in Of(player)) unit.Escort = null;
        }

        public static void Follow(PlayerCharacter player)
        {
            player.SquadHold = false;
            foreach (var unit in Of(player)) unit.Escort = null;
        }

        /// Отряд — в охрану ближайшей своей повозки. Возвращает отказ или null.
        public static string Escort(PlayerCharacter player, int owner)
        {
            CaravanActor cart = null;
            float best = float.MaxValue;
            foreach (var actor in Actor.All)
            {
                var other = actor as CaravanActor;
                if (other == null || !other.Alive || other.Trip.Owner != owner || other.Side != (int)player.Faction) continue;
                float gap = other.At.FlatDistance(player.Feet);
                if (gap < best)
                {
                    best = gap;
                    cart = other;
                }
            }
            if (cart == null) return "сопровождать нечего: своих караванов в пути нет";
            var squad = Of(player);
            if (squad.Count == 0) return "сопровождать некому: отряд пуст";
            foreach (var unit in squad) unit.Escort = cart;
            return null;
        }

        /// Куда равняется отряд: на точку приказа или на командира.
        public static V3 Anchor(PlayerCharacter player) { return player.SquadHold ? player.SquadRally : player.Feet; }

        public static float Facing(PlayerCharacter player) { return player.SquadHold ? player.SquadRallyYaw : player.Yaw; }
    }
}
