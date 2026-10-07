// Долгая партия (перенос tools/long_game_test.gd, шаг 11 плана): проходит ли
// ИИ-злодей ВСЮ хозяйственную цепочку сам — от пустых рук до войска и кузни.
// Ничего не подкладывается: мир идёт сам, и видно, где цепочка рвётся и
// сколько занимает каждое звено.
//
// В общий прогон НЕ входят ([Explicit]): мир живой, итог от раза к разу
// разнится. Запуск по имени: LongGameTests.ForElves (злодей и стража под ИИ,
// эльфом сидит неподвижный человек) и LongGameTests.ForGuard (злодей и эльфы
// под ИИ). Время ускорено вчетверо: 24 игровых минуты — шесть реальных (в
// Godot-версии кузня появлялась к 17-й минуте).
// Каждые 5 игровых секунд отмечаются звенья, раз в минуту печатается сводка
// с пометкой «[долгая]» — по ней и видно, где рвётся.
using System.Collections;
using System.Collections.Generic;
using DjvaGoda.Core;
using DjvaGoda.Game;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace DjvaGoda.Tests
{
    public class LongGameTests
    {
        const float GameMinutes = 24f;
        const float Speed = 4f;
        const float Sample = 5f;
        static readonly string[] Links = { "storage", "labourers", "caravan", "iron", "barracks", "soldier", "forge", "gear", "armor", "assault", "palace" };

        readonly Dictionary<string, float> _reached = new Dictionary<string, float>();
        MatchAi _ai;

        [UnitySetUp]
        public IEnumerator Build()
        {
            yield return TestArena.Load();
            _reached.Clear();
            _ai = Object.FindAnyObjectByType<MatchAi>();
        }

        [UnityTearDown]
        public IEnumerator Clear()
        {
            Time.timeScale = 1f;
            yield return TestArena.Clear();
        }

        [UnityTest, Explicit("долгая партия: запускать по имени"), Category("Long"), Timeout(1800000)]
        public IEnumerator ForElves() { yield return Run(Faction.Elves); }

        [UnityTest, Explicit("долгая партия: запускать по имени"), Category("Long"), Timeout(1800000)]
        public IEnumerator ForGuard() { yield return Run(Faction.Guard); }

        IEnumerator Run(Faction human)
        {
            // Человек сидит за своей стороной и ничего не делает: его сторона не под ИИ.
            var seat = TestArena.Fighter(human, Factions.Spawn[(int)human].ToUnity(), 0f);
            seat.LocalControl = true;
            _ai.RunWithoutNetwork = true;
            Object.FindAnyObjectByType<MatchGoals>().RunWithoutNetwork = true;
            yield return TestArena.Settle();

            Time.timeScale = Speed;
            float started = Time.realtimeSinceStartup;
            float game = 0f, next = Sample;
            while (game < GameMinutes * 60f && !(_reached.ContainsKey("gear") && _reached.ContainsKey("assault")))
            {
                yield return null;
                game += Time.deltaTime;
                if (game < next) continue;
                next += Sample;
                Mark(game);
            }
            Time.timeScale = 1f;
            float real = Time.realtimeSinceStartup - started;
            Debug.Log(string.Format("[долгая] за {0}: {1:F1} игровых минут за {2:F1} реальных (ускорение {3:F1})",
                Factions.Names[(int)human], game / 60f, real / 60f, game / Mathf.Max(real, 0.001f)));
            foreach (var key in Links) Debug.Log(string.Format("[долгая]   {0,-10} {1}", key, When(key)));
            Debug.Log("[долгая] казна злодея к концу: " + Stock() + ", батраков " + Builder.Crew(Faction.Villain).Count + ", бойцов " + Soldiers());

            var missing = new List<string>();
            foreach (var key in new[] { "storage", "caravan", "iron", "barracks", "soldier", "forge", "gear" })
                if (!_reached.ContainsKey(key)) missing.Add(key);
            Assert.That(missing, Is.Empty, "ИИ-злодей не дошёл по цепочке: " + string.Join(", ", missing.ToArray()));
        }

        void Mark(float game)
        {
            var wallet = Treasury.Of(Faction.Villain);
            Reach("storage", game, Builder.StorageOf(Faction.Villain) != null);
            Reach("labourers", game, Builder.Crew(Faction.Villain).Count > 0);
            int carts = 0;
            foreach (var actor in Actor.All)
                if (actor is CaravanActor && actor.Side == (int)Faction.Villain && actor.Alive) carts++;
            Reach("caravan", game, carts > 0);
            // Железо: немного с микро-шахты, основное — обозом из леса эльфов; потраченное тоже в счёт.
            Reach("iron", game, wallet.GetAmount(ResourceKind.Iron) > 0 || Has(BuildingKind.SwordBarracks) || Has(BuildingKind.ArcherBarracks));
            Reach("barracks", game, Has(BuildingKind.SwordBarracks) || Has(BuildingKind.ArcherBarracks));
            Reach("soldier", game, Soldiers() > 0);
            Reach("forge", game, Has(BuildingKind.Forge));
            var hero = _ai.HeroOf(Faction.Villain);
            Reach("gear", game, hero != null && hero.Kit.GearTier >= 1);
            Reach("armor", game, hero != null && hero.Kit.ArmorTier >= 1);
            // Штурм: войско злодея идёт на дворец; дворец — взят (в зачёт не входят, сводка).
            var band = _ai.WarbandOf(Faction.Villain);
            Reach("assault", game, band != null && band.Brain.Goal.HasValue && band.Brain.Goal.Value.FlatDistance(MatchState.Palace) < 5f);
            var goals = Object.FindAnyObjectByType<MatchGoals>();
            Reach("palace", game, goals != null && goals.State.PalaceOwner == Faction.Villain);
            if ((int)game % 60 != 0) return;
            Debug.Log(string.Format("[долгая] {0,2} мин: звеньев {1}, казна {2}, батраков {3}, бойцов {4}, обозов {5}",
                (int)(game / 60f), _reached.Count, Stock(), Builder.Crew(Faction.Villain).Count, Soldiers(), carts));
            var hands = new List<string>();
            foreach (var worker in Builder.Crew(Faction.Villain))
                hands.Add((int)worker.Brain.Role + ":" + Mathf.Round(worker.At.X) + "," + Mathf.Round(worker.At.Z) + ":" + worker.Brain.Carrying);
            Debug.Log("[долгая]      батраки (роль:где:несёт): " + string.Join(" ", hands.ToArray()));
            foreach (var actor in Actor.All)
            {
                var cart = actor as CaravanActor;
                if (cart == null || cart.Side != (int)Faction.Villain || cart.Trip == null) continue;
                Debug.Log(string.Format("[долгая]      обоз: {0} в {1},{2}, стоит {3}, ждёт {4}, груз {5}", cart.Trip.State,
                    Mathf.Round(cart.At.X), Mathf.Round(cart.At.Z), cart.Trip.Halted, cart.Trip.Waiting, cart.Trip.CargoTotal));
            }
            if (hero != null)
            {
                var brain = hero.GetComponent<HeroDriver>();
                var d = brain != null ? brain.Decision : null;
                Debug.Log(string.Format("[долгая]      вожак злодея: {0} в {1},{2}, цель {3}, оружие {4}", d != null ? d.Task.ToString() : "—",
                    Mathf.Round(hero.At.X), Mathf.Round(hero.At.Z), d != null ? Mathf.Round(d.Goal.X) + "," + Mathf.Round(d.Goal.Z) : "—", hero.Kit.GearTier));
            }
            var elves = _ai.HeroOf(Faction.Elves);
            int houses = 0;
            foreach (var actor in Actor.All)
            {
                var b = actor as BuildingActor;
                if (b != null && b.Alive && b.Side == (int)Faction.Elves && Res.IsElfHouse(b.State.Kind)) houses++;
            }
            Debug.Log("[долгая]      эльфы: домов " + houses + ", вожак ИИ " + (elves != null && elves.Alive ? "жив" : "нет")
                + "; стража: гарнизон " + _ai.GarrisonOf(Faction.Guard));
        }

        void Reach(string key, float game, bool ok)
        {
            if (!ok || _reached.ContainsKey(key)) return;
            _reached[key] = game;
            Debug.Log("[долгая] звено «" + key + "» — на " + Clock(game));
        }

        string When(string key)
        {
            float at;
            return _reached.TryGetValue(key, out at) ? "на " + Clock(at) : "не дошёл";
        }

        static string Clock(float game) { return (int)(game / 60f) + ":" + ((int)game % 60).ToString("00"); }

        static bool Has(BuildingKind kind)
        {
            foreach (var actor in Actor.All)
            {
                var b = actor as BuildingActor;
                if (b != null && b.Alive && b.Side == (int)Faction.Villain && b.State.Kind == kind && b.State.Done) return true;
            }
            return false;
        }

        static string Stock()
        {
            var wallet = Treasury.Of(Faction.Villain);
            var parts = new List<string>();
            for (int i = 0; i < Res.Count; i++) parts.Add(wallet.GetAmount(i).ToString());
            return "[" + string.Join(", ", parts.ToArray()) + "]";
        }

        /// Бойцы злодея, НАНЯТЫЕ в казарме: не гарнизон (он стоит с начала партии),
        /// не звери призыва, не распорядитель.
        static int Soldiers()
        {
            int count = 0;
            foreach (var actor in Actor.All)
            {
                var unit = actor as UnitAgent;
                if (unit == null || !unit.Alive || unit.Side != (int)Faction.Villain) continue;
                if (unit.Champion || unit.Lifetime > 0f || unit.name.StartsWith("Гарнизон")) continue;
                count++;
            }
            return count;
        }
    }
}
