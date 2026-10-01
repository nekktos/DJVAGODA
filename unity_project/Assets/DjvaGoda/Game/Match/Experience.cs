// Опыт (перенос player.gd::award_xp и world.gd::_award_kill_xp,
// award_faction_xp). За что — решение автора: за донесённые ресурсы, убийства
// и доехавшие обозы; за своих — ничего.
//
// Личное — тому, кто сделал: свою ношу в склад, убийство. Общее — вожаку
// стороны (живой человек, а если за сторону никто не сел — её герой под ИИ):
// донесённое батраками и доехавший обоз — хозяйство его дело. Опыт тратят на
// уровни (P — прокачка, Vitals.BuyLevel). Считает хост.
using System.Collections.Generic;
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public class Experience : MonoBehaviour
    {
        /// Хвост добычи на персонажа: очко стоит четыре единицы, мелкие доставки копятся.
        static readonly Dictionary<PlayerCharacter, ResourceXp> Tails = new Dictionary<PlayerCharacter, ResourceXp>();

        void Awake()
        {
            Actor.Killed += OnKilled;
            CaravanActor.Home += OnCaravanHome;
        }

        void OnDestroy()
        {
            Actor.Killed -= OnKilled;
            CaravanActor.Home -= OnCaravanHome;
            Tails.Clear();
        }

        public static void Award(PlayerCharacter player, int amount, string why)
        {
            if (player == null || amount <= 0 || !player.Alive) return;
            player.Vitals.Experience += amount;
            Debug.Log("[опыт] " + player.name + ": +" + amount + " за " + why + ", всего " + player.Vitals.Experience);
        }

        /// Донесённое до склада: очко за каждые четыре единицы, остаток копится.
        public static void ForResources(PlayerCharacter player, int units)
        {
            if (player == null || units <= 0) return;
            ResourceXp tail;
            if (!Tails.TryGetValue(player, out tail)) Tails[player] = tail = new ResourceXp();
            Award(player, tail.Award(units), "добычу");
        }

        /// Вожак стороны: живой человек, иначе её герой под ИИ.
        public static PlayerCharacter LeaderOf(Faction side)
        {
            PlayerCharacter hero = null;
            foreach (var actor in Actor.All)
            {
                var player = actor as PlayerCharacter;
                if (player == null || !player.Alive || player.Faction != side) continue;
                if (player.GetComponent<HeroDriver>() == null) return player;
                hero = player;
            }
            return hero;
        }

        /// Донесённое батраками — вожаку стороны.
        public static void ForFactionResources(Faction side, int units) { ForResources(LeaderOf(side), units); }

        static void OnKilled(Actor victim, Actor source)
        {
            var killer = source as PlayerCharacter;
            if (killer == null || victim == null || victim is BuildingActor || victim is CaravanActor || victim is HorseActor) return;
            if (victim.Side < 0 || !Factions.Hostile((int)killer.Faction, victim.Side)) return;
            var player = victim as PlayerCharacter;
            bool leader = player != null && player.Kit.IsLeader;
            Award(killer, leader ? Progression.XpLeaderKill : Progression.XpUnitKill, leader ? "убийство вожака" : "убийство");
        }

        static void OnCaravanHome(CaravanActor cart)
        {
            Award(LeaderOf((Faction)cart.Side), Progression.XpCaravan, "обоз");
        }
    }
}
