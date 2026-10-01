// Проверки шага 9, часть «б»: распорядитель стражи и старейшина эльфов в
// живой сцене (без сети). Приказ берут у живого распорядителя, засчитывают
// делом (убитые злодеи), сдают за награду; пятерых сданных хватает на
// командование; павший распорядитель уходит с поста. Старейшина даёт задание
// держать хутор, секунды капают на месте, сдача — золотом; коня не просит.
// Правила службы — ядро (CoreTests); здесь — события мира и доклад.
using System.Collections;
using DjvaGoda.Core;
using DjvaGoda.Game;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace DjvaGoda.Tests
{
    public class ServiceTests
    {
        MatchGoals _goals;

        [UnitySetUp]
        public IEnumerator Build()
        {
            yield return TestArena.Load();
            _goals = Object.FindAnyObjectByType<MatchGoals>();
            _goals.RunWithoutNetwork = true;
            for (int side = 0; side < Factions.Count; side++) Treasury.Of(side).Carried.Capacity = 5000;
            yield return TestArena.Settle();
        }

        [UnityTearDown]
        public IEnumerator Clear() { yield return TestArena.Clear(); }

        [UnityTest]
        public IEnumerator GuardTakesOrderKillsAndIsPaid()
        {
            Assert.That(Commander.Instance, Is.Not.Null, "распорядителя нет");
            Assert.That(Commander.Instance.BodyAt.HasValue, Is.True, "распорядитель не встал на пост");
            var guard = TestArena.Fighter(Faction.Guard, (Commander.Instance.BodyAt.Value + new V3(2f, 0f, 0f)).ToUnity(), 0f);
            yield return TestArena.Settle();
            guard.Service.OrdersDone = 1; // очередной по кругу — «проредить войско злодея»
            var shop = guard.GetComponent<Shop>();
            shop.ServerDeal(DealKind.Report, 0);
            Assert.That(guard.Service.Order, Is.EqualTo(OrderKind.Slay), "приказ не выдан");

            for (int i = 0; i < Orders.TargetOf(OrderKind.Slay); i++)
            {
                var villain = TestArena.Fighter(Faction.Villain, TestArena.Centre + new Vector3(3f * i, 0f, 0f), 0f);
                yield return null;
                Actor.Strike(villain, 5000f, "torso", WeaponKind.Sword, false, guard);
            }
            Assert.That(guard.Service.Done, Is.True, "убитые злодеи не засчитаны: " + guard.Service.Progress);
            int gold = Treasury.Of(Faction.Guard).GetAmount(ResourceKind.Gold);
            shop.ServerDeal(DealKind.Report, 0);
            Assert.That(Treasury.Of(Faction.Guard).GetAmount(ResourceKind.Gold), Is.EqualTo(gold + Orders.RewardOf(OrderKind.Slay)[(int)ResourceKind.Gold]),
                "награда не выплачена");
            Assert.That(guard.Service.OrdersDone, Is.EqualTo(2), "сданный приказ не засчитан");
            Assert.That(guard.Service.Order.HasValue, Is.True, "следующий приказ не выдан");
        }

        [UnityTest]
        public IEnumerator PromotionAndFallenCommander()
        {
            var post = Commander.Instance.BodyAt.Value;
            var guard = TestArena.Fighter(Faction.Guard, (post + new V3(2f, 0f, 0f)).ToUnity(), 0f);
            yield return TestArena.Settle();
            var shop = guard.GetComponent<Shop>();
            shop.ServerDeal(DealKind.Promote, 0);
            Assert.That(guard.Kit.IsLeader, Is.False, "командование без службы");
            guard.Service.OrdersDone = Orders.OrdersForPromotion;
            shop.ServerDeal(DealKind.Promote, 0);
            Assert.That(guard.Kit.IsLeader, Is.True, "командование за пять приказов не дано");

            // Распорядителя убили — поста нет, доклад не принимается.
            UnitAgent body = null;
            foreach (var actor in Actor.All)
            {
                var unit = actor as UnitAgent;
                if (unit != null && unit.Champion && unit.Side == (int)Faction.Guard) body = unit;
            }
            Assert.That(body, Is.Not.Null, "тела распорядителя нет");
            var villain = TestArena.Fighter(Faction.Villain, TestArena.Centre, 0f);
            Actor.Strike(body, 50000f, "torso", WeaponKind.Sword, false, villain);
            yield return null;
            yield return null;
            Assert.That(Commander.Instance.Post.OnDuty, Is.False, "павший распорядитель на посту");
            Assert.That(Commander.Instance.InRange(guard.Feet), Is.False, "с павшим можно говорить");
        }

        [UnityTest]
        public IEnumerator ElderTaskHoldHamlet()
        {
            Assert.That(Elder.Instance.BodyAt.HasValue, Is.True, "старейшина не встал");
            var elf = TestArena.Fighter(Faction.Elves, (Elder.Instance.BodyAt.Value + new V3(2f, 0f, 0f)).ToUnity(), 0f);
            yield return TestArena.Settle();
            var shop = elf.GetComponent<Shop>();
            elf.Tasks.TasksDone = 4; // «пригнать коня» — ездить не на ком: пропустить
            shop.ServerDeal(DealKind.Report, 0);
            Assert.That(elf.Tasks.Task, Is.Not.EqualTo(ElfTaskKind.Horse), "старейшина просит коня, которого нет");

            elf.Tasks.Task = null;
            elf.Tasks.TasksDone = 3; // «вернуть землю»
            shop.ServerDeal(DealKind.Report, 0);
            Assert.That(elf.Tasks.Task, Is.EqualTo(ElfTaskKind.Reclaim));
            var home = elf.transform.position;
            elf.Teleport(TestArena.Ground(MapLayout.Hamlets[3].ToUnity()) + Vector3.up * 0.05f);
            yield return TestArena.Wait(ElfTasks.TargetOf(ElfTaskKind.Reclaim) + 1.5f);
            Assert.That(elf.Tasks.Done, Is.True, "хутор не засчитан: " + elf.Tasks.Progress);
            elf.Teleport(home);
            yield return TestArena.Settle();
            int gold = Treasury.Of(Faction.Elves).GetAmount(ResourceKind.Gold);
            shop.ServerDeal(DealKind.Report, 0);
            Assert.That(Treasury.Of(Faction.Elves).GetAmount(ResourceKind.Gold), Is.GreaterThan(gold), "золото за задание не выплачено");
        }
    }
}
