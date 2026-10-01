// Проверки шага 6, часть «д»: голод артели в живой сцене. Кормёжку хост
// зовёт раз в пять минут — здесь её зовут напрямую (MatchNet.Feed). Правила —
// ядро (Hunger, CoreTests): не хватило на всех — не ест никто, смерть с
// третьего пропуска; здесь — что мир убирает умерших и говорит стороне.
using System.Collections;
using DjvaGoda.Core;
using DjvaGoda.Game;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace DjvaGoda.Tests
{
    public class HungerTests
    {
        [UnitySetUp]
        public IEnumerator Build() { yield return TestArena.Load(); }

        [UnityTearDown]
        public IEnumerator Clear() { yield return TestArena.Clear(); }

        static PlayerCharacter VillainWithCrew(int food)
        {
            var villain = TestArena.Fighter(Faction.Villain, Factions.Spawn[(int)Faction.Villain].ToUnity(), 0f);
            villain.Kit.IsLeader = true;
            var wallet = Treasury.Of(Faction.Villain);
            wallet.Carried.Capacity = 5000;
            wallet.Carried.Amounts = new[] { 0, 0, 2000, 0, food, 0 };
            return villain;
        }

        [UnityTest]
        public IEnumerator StarvingCrewDiesAndSideIsTold()
        {
            var villain = VillainWithCrew(0);
            yield return TestArena.Settle();
            var builder = villain.GetComponent<Builder>();
            builder.ServerLabour(-1);
            builder.ServerLabour(-1);
            yield return null;
            Assert.That(Builder.Crew(Faction.Villain).Count, Is.EqualTo(2));
            for (int meal = 1; meal < Res.HungerFatal; meal++)
            {
                MatchNet.Feed();
                yield return null;
                Assert.That(Builder.Crew(Faction.Villain).Count, Is.EqualTo(2), "умерли раньше " + Res.HungerFatal + "-го пропуска");
                foreach (var worker in Builder.Crew(Faction.Villain)) Assert.That(worker.Hungry, Is.True, "голодный не помечен");
            }
            Assert.That(villain.GetComponent<PlayerCombat>().Refusal, Does.Contain("ГОЛОД"), "сторона не услышала о голоде");
            MatchNet.Feed();
            yield return null;
            Assert.That(Builder.Crew(Faction.Villain).Count, Is.EqualTo(0), "с " + Res.HungerFatal + "-го пропуска артель жива");
        }

        [UnityTest]
        public IEnumerator FedCrewIsNotHungry()
        {
            var villain = VillainWithCrew(100);
            yield return TestArena.Settle();
            villain.GetComponent<Builder>().ServerLabour(-1);
            yield return null;
            MatchNet.Feed();
            var crew = Builder.Crew(Faction.Villain);
            Assert.That(crew.Count, Is.EqualTo(1));
            Assert.That(crew[0].Hungry, Is.False, "сытый батрак помечен голодным");
            Assert.That(Treasury.Of(Faction.Villain).GetAmount(ResourceKind.Food), Is.EqualTo(100 - Res.FeedPerWorker), "еда не списана");
        }
    }
}
