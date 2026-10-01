// Проверки шага 9, часть «а»: исход партии в живой сцене (без сети:
// MatchGoals.RunWithoutNetwork). Злодей в круге дворца берёт его — стража с
// постройками и казной переходит к нему, эльфов нет — злодей побеждает; вожак
// злодея пал от руки эльфа — злодей выбыл, убийца назван. Правила — ядро
// (MatchState в CoreTests); здесь — снимок мира и объявления.
using System.Collections;
using DjvaGoda.Core;
using DjvaGoda.Game;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace DjvaGoda.Tests
{
    public class GoalsTests
    {
        MatchGoals _goals;

        [UnitySetUp]
        public IEnumerator Build()
        {
            yield return TestArena.Load();
            _goals = Object.FindAnyObjectByType<MatchGoals>();
            Assert.That(_goals, Is.Not.Null, "в сцене нет MatchGoals");
        }

        [UnityTearDown]
        public IEnumerator Clear() { yield return TestArena.Clear(); }

        static bool Said(MatchGoals goals, string part)
        {
            foreach (var entry in goals.Feed) if (entry.Key.Contains(part)) return true;
            return false;
        }

        [UnityTest]
        public IEnumerator VillainTakesPalaceAbsorbsGuardAndWins()
        {
            var storage = BuildingActor.Spawn(BuildingKind.Storage, Faction.Guard, MatchState.Palace + new V3(60f, 0f, 0f), true, null);
            Treasury.Of(Faction.Guard).Carried.Amounts = new[] { 0, 0, 77, 0, 0, 0 };
            var villain = TestArena.Fighter(Faction.Villain, MatchState.Palace.ToUnity(), 0f);
            villain.Kit.IsLeader = true;
            yield return TestArena.Settle();
            int gold = Treasury.Of(Faction.Villain).GetAmount(ResourceKind.Gold);
            // Почти взят: не ждать двадцать секунд.
            _goals.State.Claimant = (int)Faction.Villain;
            _goals.State.CaptureProgress = 0.95f;
            _goals.RunWithoutNetwork = true;
            yield return TestArena.Wait(1.5f);
            Assert.That(_goals.State.PalaceOwner, Is.EqualTo(Faction.Villain), "дворец не взят; прогресс " + _goals.State.CaptureProgress);
            Assert.That(_goals.State.GuardAbsorbed, Is.True, "стража не перешла к злодею");
            Assert.That(Factions.Hostile((int)Faction.Guard, (int)Faction.Villain), Is.False, "стража всё ещё враг злодею");
            Assert.That(storage.Side, Is.EqualTo((int)Faction.Villain), "склад стражи не перешёл к злодею");
            Assert.That(Treasury.Of(Faction.Villain).GetAmount(ResourceKind.Gold), Is.EqualTo(gold + 77), "казна стражи не перешла");
            yield return TestArena.Wait(MatchState.CheckInterval + 0.5f);
            Assert.That(_goals.State.Out[(int)Faction.Guard], Is.True, "стража не выбыла");
            Assert.That(_goals.State.Out[(int)Faction.Elves], Is.True, "эльфы без домов и живых не выбыли");
            Assert.That(_goals.State.Victors[(int)Faction.Villain], Is.True, "злодей один, а победы нет");
            Assert.That(Said(_goals, "ПОБЕДА"), Is.True, "победа не объявлена");
        }

        [UnityTest]
        public IEnumerator VillainLeaderFallsToElf()
        {
            var villain = TestArena.Fighter(Faction.Villain, TestArena.Centre, 0f);
            villain.Kit.IsLeader = true;
            var elf = TestArena.Fighter(Faction.Elves, TestArena.Centre + new Vector3(1.5f, 0f, 0f), 0f);
            _goals.RunWithoutNetwork = true;
            yield return TestArena.Settle();
            Actor.Strike(villain, 5000f, "torso", WeaponKind.Sword, false, elf);
            yield return null;
            yield return null;
            Assert.That(_goals.State.LeaderDown[(int)Faction.Villain], Is.True, "павший вожак не замечен");
            Assert.That(_goals.State.Out[(int)Faction.Villain], Is.True, "злодей без вожака не выбыл");
            Assert.That(Said(_goals, Factions.Names[(int)Faction.Elves]), Is.True, "убийца вожака не назван");
            Assert.That(_goals.State.Out[(int)Faction.Guard], Is.False, "стража выбыла без причины");
        }
    }
}
