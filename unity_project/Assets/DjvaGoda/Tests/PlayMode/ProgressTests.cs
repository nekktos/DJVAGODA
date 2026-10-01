// Проверки опыта и прокачки в живой сцене (без сети). Убил врага — опыт
// убийце, вожака — больше; донёс ношу до склада — очко за четыре единицы;
// опыт тратится на уровень (P) — здоровье растёт сразу, без опыта — отказ.
// Цены и шкала — Progression ядра.
using System.Collections;
using DjvaGoda.Core;
using DjvaGoda.Game;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace DjvaGoda.Tests
{
    public class ProgressTests
    {
        [UnitySetUp]
        public IEnumerator Build() { yield return TestArena.Load(); }

        [UnityTearDown]
        public IEnumerator Clear() { yield return TestArena.Clear(); }

        [UnityTest]
        public IEnumerator KillsGiveExperience()
        {
            var elf = TestArena.Fighter(Faction.Elves, TestArena.Centre, 0f);
            var guard = TestArena.Fighter(Faction.Guard, TestArena.Centre + new Vector3(2f, 0f, 0f), 0f);
            var villain = TestArena.Fighter(Faction.Villain, TestArena.Centre + new Vector3(4f, 0f, 0f), 0f);
            villain.Kit.IsLeader = true;
            yield return TestArena.Settle();
            Actor.Strike(guard, 5000f, "torso", WeaponKind.Sword, false, elf);
            Assert.That(elf.Vitals.Experience, Is.EqualTo(Progression.XpUnitKill), "за убийство стража нет опыта");
            Actor.Strike(villain, 5000f, "torso", WeaponKind.Sword, false, elf);
            Assert.That(elf.Vitals.Experience, Is.EqualTo(Progression.XpUnitKill + Progression.XpLeaderKill), "за вожака не больше");
        }

        [UnityTest]
        public IEnumerator DepositGivesExperience()
        {
            var fort = Factions.Spawn[(int)Faction.Villain];
            BuildingActor.Spawn(BuildingKind.Storage, Faction.Villain, fort + new V3(12f, 0f, 0f), true, null);
            var villain = TestArena.Fighter(Faction.Villain, (fort + new V3(12f, 0f, 8f)).ToUnity(), 0f);
            var wallet = Treasury.Of(Faction.Villain);
            wallet.Carried.Capacity = 500;
            wallet.Carried.Amounts = new[] { 21, 0, 0, 0, 0, 0 };
            yield return TestArena.Wait(Res.DepositInterval + 1f);
            Assert.That(wallet.Carried.GetAmount(0), Is.EqualTo(0), "ноша не сдана в склад");
            Assert.That(villain.Vitals.Experience, Is.EqualTo(21 / Progression.ResourcePerPoint), "опыт за добычу не тот");
        }

        [UnityTest]
        public IEnumerator BuyLevel()
        {
            var me = TestArena.Fighter(Faction.Guard, TestArena.Centre, 0f);
            yield return TestArena.Settle();
            var shop = me.GetComponent<Shop>();
            float health = me.Vitals.MaxHealth;
            shop.Request(DealKind.Upgrade, (int)Stat.Health);
            Assert.That(me.Vitals.Levels[(int)Stat.Health], Is.EqualTo(0), "уровень без опыта");
            me.Vitals.Experience = Progression.CostOf(0);
            shop.Request(DealKind.Upgrade, (int)Stat.Health);
            Assert.That(me.Vitals.Levels[(int)Stat.Health], Is.EqualTo(1), "уровень за опыт не куплен");
            Assert.That(me.Vitals.MaxHealth, Is.GreaterThan(health), "здоровье не выросло");
            Assert.That(me.Vitals.Experience, Is.EqualTo(0), "опыт не списан");
        }
    }
}
