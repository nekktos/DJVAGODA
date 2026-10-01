// Проверки шага 7 «ИИ» в живой сцене (без сети: MatchAi.RunWithoutNetwork).
// Старт партии — хозяйство стражи и дома эльфов; стороны без людей — гарнизоны,
// отряды, распорядитель злодея, герои злодея и эльфов; сел человек — гарнизон
// распущен; герой злодея без склада копает микро-шахту, герой эльфов добывает
// лес или ставит дом. Решения — мозги ядра (CoreTests); здесь — руки.
using System.Collections;
using DjvaGoda.Core;
using DjvaGoda.Game;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace DjvaGoda.Tests
{
    public class AiTests
    {
        MatchAi _ai;

        [UnitySetUp]
        public IEnumerator Build()
        {
            yield return TestArena.Load();
            _ai = Object.FindAnyObjectByType<MatchAi>();
            Assert.That(_ai, Is.Not.Null, "в сцене нет MatchAi");
        }

        [UnityTearDown]
        public IEnumerator Clear() { yield return TestArena.Clear(); }

        static int Buildings(Faction side, BuildingKind kind)
        {
            int n = 0;
            foreach (var b in Object.FindObjectsByType<BuildingActor>(FindObjectsSortMode.None))
                if (b.State != null && b.Side == (int)side && b.State.Kind == kind) n++;
            return n;
        }

        [UnityTest]
        public IEnumerator FreeSidesGetEstateGarrisonsAndHeroes()
        {
            _ai.RunWithoutNetwork = true;
            yield return TestArena.Wait(0.5f);
            Assert.That(Buildings(Faction.Guard, BuildingKind.SwordBarracks), Is.EqualTo(1), "казармы стражи нет");
            Assert.That(Buildings(Faction.Guard, BuildingKind.Storage), Is.EqualTo(1), "склада стражи нет");
            Assert.That(Buildings(Faction.Elves, BuildingKind.ElfHouse), Is.EqualTo(Respawn.ElfHousesStart.Length), "домов эльфов не три");
            for (int side = 0; side < Factions.Count; side++)
                Assert.That(_ai.GarrisonOf((Faction)side), Is.EqualTo(AiStats.GarrisonSize), "гарнизон " + Factions.Names[side]);
            Assert.That(_ai.HeroOf(Faction.Villain), Is.Not.Null, "героя злодея нет");
            Assert.That(_ai.HeroOf(Faction.Elves), Is.Not.Null, "героя эльфов нет");
            Assert.That(_ai.HeroOf(Faction.Guard), Is.Null, "стража без вожака-ИИ, а он есть");
            Assert.That(Object.FindAnyObjectByType<StewardDriver>(), Is.Not.Null, "распорядителя злодея нет");
            Assert.That(Treasury.Of(Faction.Guard).Stored.Capacity, Is.GreaterThan(0), "склад стражи не поднял потолок");
        }

        [UnityTest]
        public IEnumerator HumanSeatDisbandsGarrison()
        {
            var guard = TestArena.Fighter(Faction.Guard, TestArena.Centre, 0f);
            guard.LocalControl = true;
            _ai.RunWithoutNetwork = true;
            yield return TestArena.Wait(0.5f);
            Assert.That(_ai.GarrisonOf(Faction.Guard), Is.EqualTo(0), "у занятой стороны стоит гарнизон");
            Assert.That(_ai.GarrisonOf(Faction.Villain), Is.EqualTo(AiStats.GarrisonSize), "у свободной стороны гарнизона нет");
        }

        [UnityTest]
        public IEnumerator VillainHeroDigsMicroMine()
        {
            _ai.RunWithoutNetwork = true;
            yield return TestArena.Wait(0.5f);
            var hero = _ai.HeroOf(Faction.Villain);
            var wallet = Treasury.Of(Faction.Villain);
            int before = wallet.GetAmount(ResourceKind.Stone) + wallet.GetAmount(ResourceKind.Gold);
            float t = 0f;
            while (t < 60f && wallet.GetAmount(ResourceKind.Stone) + wallet.GetAmount(ResourceKind.Gold) == before)
            {
                t += Time.deltaTime;
                yield return null;
            }
            Assert.That(wallet.GetAmount(ResourceKind.Stone) + wallet.GetAmount(ResourceKind.Gold), Is.GreaterThan(before),
                "герой злодея за минуту ничего не добыл с микро-шахты; он в " + hero.Feet
                + ", дело " + hero.GetComponent<HeroDriver>().Decision.Task);
        }

        /// Долгая партия в малом: три стороны под ИИ полторы минуты. Любая
        /// ошибка в консоли роняет проверку (LogAssert); злодей должен сдвинуть
        /// хозяйство с нуля — добыть или нанять.
        [UnityTest]
        public IEnumerator ThreeAiSidesRunWithoutErrors()
        {
            _ai.RunWithoutNetwork = true;
            yield return TestArena.Wait(0.5f);
            var wallet = Treasury.Of(Faction.Villain);
            int start = 0;
            for (int i = 0; i < Res.Count; i++) start += wallet.GetAmount(i);
            yield return TestArena.Wait(90f);
            int now = 0;
            for (int i = 0; i < Res.Count; i++) now += wallet.GetAmount(i);
            int crew = Builder.Crew(Faction.Villain).Count;
            Assert.That(now > start || crew > 0, Is.True, "за полторы минуты хозяйство злодея не сдвинулось: запас " + now + ", батраков " + crew);
            Assert.That(Buildings(Faction.Guard, BuildingKind.SwordBarracks), Is.EqualTo(1), "казарма стражи пала за полторы минуты без людей");
        }

        [UnityTest]
        public IEnumerator ElfHeroChopsOrBuilds()
        {
            _ai.RunWithoutNetwork = true;
            yield return TestArena.Wait(0.5f);
            var hero = _ai.HeroOf(Faction.Elves);
            var wallet = Treasury.Of(Faction.Elves);
            int wood = wallet.GetAmount(ResourceKind.Wood);
            int houses = Buildings(Faction.Elves, BuildingKind.ElfHouse);
            float t = 0f;
            while (t < 60f && wallet.GetAmount(ResourceKind.Wood) == wood && Buildings(Faction.Elves, BuildingKind.ElfHouse) == houses)
            {
                t += Time.deltaTime;
                yield return null;
            }
            Assert.That(wallet.GetAmount(ResourceKind.Wood) != wood || Buildings(Faction.Elves, BuildingKind.ElfHouse) > houses, Is.True,
                "герой эльфов за минуту не добыл леса и не поставил дом; он в " + hero.Feet
                + ", дело " + hero.GetComponent<HeroDriver>().Decision.Task);
        }
    }
}
