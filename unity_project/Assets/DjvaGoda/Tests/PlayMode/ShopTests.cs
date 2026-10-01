// Проверки шага 6, часть «в»: сделки у места в живой сцене — своя лавка,
// своя кузня, своя постройка, зелья. Цены и правила — ядро (CoreTests); здесь —
// что хост узнаёт место по положению персонажа и исполняет сделку.
using System.Collections;
using DjvaGoda.Core;
using DjvaGoda.Game;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace DjvaGoda.Tests
{
    public class ShopTests
    {
        [UnitySetUp]
        public IEnumerator Build() { yield return TestArena.Load(); }

        [UnityTearDown]
        public IEnumerator Clear() { yield return TestArena.Clear(); }

        static void Rich(Faction side)
        {
            var wallet = Treasury.Of(side);
            wallet.Carried.Capacity = 5000;
            wallet.Carried.Amounts = new[] { 2000, 2000, 2000, 2000, 2000, 2000 };
        }

        [UnityTest]
        public IEnumerator ArrowsOnlyAtOwnTrader()
        {
            var trader = MapLayout.Traders[(int)Faction.Guard].ToUnity();
            var guard = TestArena.Fighter(Faction.Guard, trader + new Vector3(3f, 0f, 0f), 0f);
            var far = TestArena.Fighter(Faction.Guard, TestArena.Centre, 0f);
            yield return TestArena.Settle();
            Rich(Faction.Guard);
            guard.Kit.Arrows = 0;
            far.Kit.Arrows = 0;
            guard.GetComponent<Shop>().ServerDeal(DealKind.Trade, (int)TradeItem.Arrows);
            far.GetComponent<Shop>().ServerDeal(DealKind.Trade, (int)TradeItem.Arrows);
            Assert.That(guard.Kit.Arrows, Is.EqualTo(Res.ArrowPack), "у своей лавки стрелы не куплены");
            Assert.That(far.Kit.Arrows, Is.EqualTo(0), "стрелы куплены вдали от лавки");
        }

        [UnityTest]
        public IEnumerator ForgeOnlyAtOwnForge()
        {
            var villain = TestArena.Fighter(Faction.Villain, TestArena.Centre, 0f);
            villain.Kit.IsLeader = true;
            yield return TestArena.Settle();
            Rich(Faction.Villain);
            var shop = villain.GetComponent<Shop>();
            shop.ServerDeal(DealKind.Forge, 0);
            Assert.That(villain.Kit.GearTier, Is.EqualTo(0), "закалили без кузни");
            Assert.That(villain.GetComponent<PlayerCombat>().Refusal, Does.Contain("кузн"), "отказ без кузни не объяснён");
            var at = TestArena.Ground(TestArena.Centre + new Vector3(0f, 0f, 8f)).ToCore();
            BuildingActor.Spawn(BuildingKind.Forge, Faction.Villain, at, true, null);
            yield return null;
            shop.ServerDeal(DealKind.Forge, 0);
            Assert.That(villain.Kit.GearTier, Is.EqualTo(1), "у своей кузни не закалили");
        }

        [UnityTest]
        public IEnumerator FortifyOwnStorage()
        {
            var villain = TestArena.Fighter(Faction.Villain, TestArena.Centre, 0f);
            villain.Kit.IsLeader = true;
            yield return TestArena.Settle();
            Rich(Faction.Villain);
            var at = TestArena.Ground(TestArena.Centre + new Vector3(0f, 0f, 9f)).ToCore();
            var storage = BuildingActor.Spawn(BuildingKind.Storage, Faction.Villain, at, true, null);
            yield return null;
            float health = storage.State.MaxHealth;
            villain.GetComponent<Shop>().ServerDeal(DealKind.Fortify, 0);
            Assert.That(storage.State.Grade, Is.EqualTo(1), "склад не укреплён");
            Assert.That(storage.State.MaxHealth, Is.GreaterThan(health), "ступень не прибавила прочности");
        }

        [UnityTest]
        public IEnumerator PotionHeals()
        {
            var guard = TestArena.Fighter(Faction.Guard, TestArena.Centre, 0f);
            yield return TestArena.Settle();
            guard.Kit.PotionsHeal = 1;
            guard.Vitals.Health = 30f;
            guard.GetComponent<Shop>().ServerDeal(DealKind.Potion, 1);
            Assert.That(guard.Vitals.Health, Is.GreaterThan(30f), "зелье не вылечило");
            Assert.That(guard.Kit.PotionsHeal, Is.EqualTo(0), "зелье не убыло");
        }
    }
}
