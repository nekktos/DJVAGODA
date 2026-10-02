// Проверки шага 8 «Ранения» в живой сцене (без сети). Отрубленная рука падает
// на землю, поднявший получает трофей; павший роняет кучу со всем, что было
// при нём, куча подбирается; деревянный протез ставится где угодно, а лубок —
// только у верстака. Правила ран и цены — ядро (CoreTests); здесь — руки.
using System.Collections;
using DjvaGoda.Core;
using DjvaGoda.Game;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace DjvaGoda.Tests
{
    public class WoundTests
    {
        [UnitySetUp]
        public IEnumerator Build() { yield return TestArena.Load(); }

        [UnityTearDown]
        public IEnumerator Clear() { yield return TestArena.Clear(); }

        [UnityTest]
        public IEnumerator SeveredArmDropsAndBecomesTrophy()
        {
            var victim = TestArena.Fighter(Faction.Elves, TestArena.Centre, 0f);
            var hitter = TestArena.Fighter(Faction.Villain, TestArena.Centre + new Vector3(1.5f, 0f, 0f), 0f);
            yield return TestArena.Settle();
            for (int i = 0; i < 4 && !victim.Body.IsSevered(Limb.ArmL) && victim.Alive; i++)
                Actor.Strike(victim, 30f, "arm_l", WeaponKind.Sword, false, hitter);
            Assert.That(victim.Body.IsSevered(Limb.ArmL), Is.True, "рука не отрублена");
            Assert.That(Pickup.All.Count, Is.EqualTo(1), "отрубленная рука не упала");
            Assert.That(Pickup.All[0].Kind, Is.EqualTo(PickupKind.Arm));

            hitter.GetComponent<Shop>().ServerDeal(DealKind.Pickup, 0);
            yield return null;
            Assert.That(hitter.Trophies[(int)TrophyKind.Arms], Is.EqualTo(1), "поднятая рука не стала трофеем");
            Assert.That(Pickup.All.Count, Is.EqualTo(0), "рука осталась лежать");
        }

        [UnityTest]
        public IEnumerator DeathDropsLootThatCanBeCollected()
        {
            var victim = TestArena.Fighter(Faction.Elves, TestArena.Centre, 0f);
            var looter = TestArena.Fighter(Faction.Villain, TestArena.Centre + new Vector3(1.5f, 0f, 0f), 0f);
            victim.Kit.ArmorTier = 2;
            victim.Kit.PotionsHeal = 2;
            Treasury.Of(Faction.Elves).Carried.Capacity = 500;
            Treasury.Of(Faction.Elves).Add((int)ResourceKind.Wood, 40);
            yield return TestArena.Settle();
            int corpses = Corpses.Count;
            Actor.Strike(victim, 5000f, "torso", WeaponKind.Sword, false, looter);
            yield return null;
            yield return null;
            Assert.That(victim.Alive, Is.False, "павший жив");
            Assert.That(Corpses.Count, Is.EqualTo(corpses + 1), "труп не лёг");
            Assert.That(Pickup.All.Count, Is.EqualTo(1), "куча с павшего не упала");
            var pile = Pickup.All[0].Pile;
            Assert.That(pile.Armor, Is.EqualTo(2), "доспех не в куче");
            Assert.That(pile.Contents[(int)ResourceKind.Wood], Is.EqualTo(40), "ноша не в куче");
            Assert.That(victim.Kit.ArmorTier, Is.EqualTo(0), "доспех остался на павшем");
            Assert.That(Treasury.Of(Faction.Elves).Carried.GetAmount((int)ResourceKind.Wood), Is.EqualTo(0), "ноша осталась у стороны");

            Treasury.Of(Faction.Villain).Carried.Capacity = 500;
            looter.GetComponent<Shop>().ServerDeal(DealKind.Pickup, 0);
            yield return null;
            Assert.That(looter.Kit.ArmorTier, Is.EqualTo(2), "доспех из кучи не надет");
            Assert.That(looter.Kit.PotionsHeal, Is.GreaterThan(0), "зелья из кучи не взяты");
            Assert.That(Treasury.Of(Faction.Villain).GetAmount(ResourceKind.Wood), Is.EqualTo(40), "ноша из кучи не взята");
            Assert.That(Pickup.All.Count, Is.EqualTo(0), "куча не исчезла");
        }

        [UnityTest]
        public IEnumerator WoodenProstheticAnywhereSplintOnlyAtBench()
        {
            var me = TestArena.Fighter(Faction.Guard, TestArena.Centre, 0f);
            var wallet = Treasury.Of(Faction.Guard);
            wallet.Carried.Capacity = 1000;
            wallet.Carried.Amounts = new[] { 200, 200, 200, 200, 0, 0 };
            me.Body.RegisterHit("arm_r", 100f, WeaponKind.Axe);
            me.Body.RegisterHit("leg_l", 100f, WeaponKind.Hammer);
            yield return TestArena.Settle();
            var shop = me.GetComponent<Shop>();

            shop.ServerDeal(DealKind.Workbench, (int)BenchOp.Prosthetic * 10 + 1);
            Assert.That(me.Body.Tier(Limb.ArmR), Is.EqualTo(1), "деревянный протез вдали от верстака не поставлен");
            shop.ServerDeal(DealKind.Workbench, (int)BenchOp.Splint * 10);
            Assert.That(me.Body.IsCrippled(Limb.LegL), Is.True, "кость вправлена вдали от верстака");

            me.Teleport(TestArena.Ground(MapLayout.Workbench.ToUnity()) + Vector3.up * 0.05f);
            yield return TestArena.Settle();
            Assert.That(shop.AtBench, Is.True, "у верстака, а верстака нет");
            shop.ServerDeal(DealKind.Workbench, (int)BenchOp.Splint * 10);
            Assert.That(me.Body.IsCrippled(Limb.LegL), Is.False, "кость у верстака не вправлена");
            shop.ServerDeal(DealKind.Workbench, (int)BenchOp.Prosthetic * 10 + BodyState.NecroticTier);
            Assert.That(me.Body.Tier(Limb.ArmR), Is.EqualTo(1), "некротический протез без трофеев поставлен");
            me.Trophies[(int)TrophyKind.Arms] = BodyState.NecroticPrice;
            shop.ServerDeal(DealKind.Workbench, (int)BenchOp.Prosthetic * 10 + BodyState.NecroticTier);
            Assert.That(me.Body.Tier(Limb.ArmR), Is.EqualTo(BodyState.NecroticTier), "некротический протез за трофеи не поставлен");
            Assert.That(me.Trophies[(int)TrophyKind.Arms], Is.EqualTo(0), "трофеи не списаны");
        }
    }
}
