// Консоль плейтеста: команды хоста делают то, что обещают (Cheats.Run).
using System.Collections;
using DjvaGoda.Core;
using DjvaGoda.Game;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace DjvaGoda.Tests
{
    public class CheatTests
    {
        [UnitySetUp]
        public IEnumerator Build() { yield return TestArena.Load(); }

        [UnityTearDown]
        public IEnumerator Clear() { yield return TestArena.Clear(); }

        [UnityTest]
        public IEnumerator CommandsDoWhatTheySay()
        {
            var me = TestArena.Fighter(Faction.Villain, TestArena.Centre, 0f);
            yield return TestArena.Settle();
            int iron = Treasury.Of(Faction.Villain).GetAmount((int)ResourceKind.Iron);
            Cheats.Run(me, "res 0 0 0 50");
            Assert.That(Treasury.Of(Faction.Villain).GetAmount((int)ResourceKind.Iron), Is.EqualTo(iron + 50), "res не выдал железа");
            Cheats.Run(me, "xp 300");
            Assert.That(me.Vitals.Experience, Is.GreaterThanOrEqualTo(300), "xp не дал опыта");
            Cheats.Run(me, "limb arm_r");
            Assert.That(me.Body.IsSevered(Limb.ArmR), Is.True, "limb не оторвал");
            Cheats.Run(me, "heal");
            Assert.That(me.Body.IsSevered(Limb.ArmR), Is.False, "heal не вернул руку");
            Cheats.Run(me, "goto bench");
            yield return null;
            Assert.That(me.At.FlatDistance(MapLayout.Workbench), Is.LessThan(6f), "goto bench не перенёс к верстаку");
            Assert.That(Cheats.Run(me, "нечто"), Does.StartWith("нет такой команды"));
        }
    }
}
