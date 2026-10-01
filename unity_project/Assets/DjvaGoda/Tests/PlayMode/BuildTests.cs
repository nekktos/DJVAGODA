// Проверки шага 6, часть «б»: постройки в живой сцене. Злодей ставит склад —
// ресурсы списаны, склад растёт и, достроенный, поднимает стороне потолок;
// поверх стоящего и без ресурсов не ставится; дом эльфа — только рядом с собой;
// разрушенная постройка исчезает. Правила (цены, зазор, лимит) — в ядре.
using System.Collections;
using DjvaGoda.Core;
using DjvaGoda.Game;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace DjvaGoda.Tests
{
    public class BuildTests
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

        static int Count(BuildingKind kind)
        {
            int n = 0;
            foreach (var b in Object.FindObjectsByType<BuildingActor>(FindObjectsSortMode.None))
                if (b.State != null && b.State.Kind == kind && b.Alive) n++;
            return n;
        }

        static BuildingActor Find(BuildingKind kind)
        {
            foreach (var b in Object.FindObjectsByType<BuildingActor>(FindObjectsSortMode.None))
                if (b.State != null && b.State.Kind == kind) return b;
            return null;
        }

        [UnityTest]
        public IEnumerator VillainBuildsStorageThatRaisesCapacity()
        {
            var villain = TestArena.Fighter(Faction.Villain, TestArena.Centre, 0f);
            villain.Kit.IsLeader = true;
            yield return TestArena.Settle();
            Rich(Faction.Villain);
            var wallet = Treasury.Of(Faction.Villain);
            int wood = wallet.GetAmount(ResourceKind.Wood);
            var at = TestArena.Ground(TestArena.Centre + new Vector3(0f, 0f, 25f)).ToCore();
            villain.GetComponent<Builder>().ServerBuild(BuildingKind.Storage, at);
            yield return null;
            var storage = Find(BuildingKind.Storage);
            Assert.That(storage, Is.Not.Null, "склад не поставлен");
            Assert.That(storage.State.Done, Is.False, "склад встал сразу достроенным");
            Assert.That(wallet.GetAmount(ResourceKind.Wood), Is.EqualTo(wood - Res.At(Res.BuildingCost(BuildingKind.Storage), ResourceKind.Wood)),
                "цена склада не списана");
            float progress = storage.State.Progress;
            yield return TestArena.Wait(0.5f);
            Assert.That(storage.State.Progress, Is.GreaterThan(progress), "стройка не идёт");

            int capacity = wallet.Stored.Capacity;
            storage.State.Progress = 0.999f;
            yield return TestArena.Wait(0.5f);
            Assert.That(storage.State.Done, Is.True, "склад не достроился");
            Assert.That(wallet.Stored.Capacity, Is.EqualTo(capacity + Res.StorageBonus), "достроенный склад не поднял потолок");
        }

        [UnityTest]
        public IEnumerator NoBuildOnTopOrWithoutResources()
        {
            var villain = TestArena.Fighter(Faction.Villain, TestArena.Centre, 0f);
            villain.Kit.IsLeader = true;
            yield return TestArena.Settle();
            Rich(Faction.Villain);
            var at = TestArena.Ground(TestArena.Centre + new Vector3(0f, 0f, 25f)).ToCore();
            var builder = villain.GetComponent<Builder>();
            builder.ServerBuild(BuildingKind.Storage, at);
            yield return null;
            builder.ServerBuild(BuildingKind.Storage, at + new V3(2f, 0f, 0f));
            yield return null;
            Assert.That(Count(BuildingKind.Storage), Is.EqualTo(1), "склад встал поверх стоящего");
            Assert.That(villain.GetComponent<PlayerCombat>().Refusal, Does.Contain("нельзя"), "отказ не объяснён");

            Treasury.Of(Faction.Villain).Carried.Amounts = Res.Empty();
            builder.ServerBuild(BuildingKind.Farm, at + new V3(60f, 0f, 0f));
            yield return null;
            Assert.That(Count(BuildingKind.Farm), Is.EqualTo(0), "поле встало без ресурсов");
            Assert.That(villain.GetComponent<PlayerCombat>().Refusal, Does.Contain("не хватает"), "отказ без ресурсов не объяснён");
        }

        [UnityTest]
        public IEnumerator ElfHouseOnlyNearby()
        {
            var elf = TestArena.Fighter(Faction.Elves, TestArena.Centre, 0f);
            yield return TestArena.Settle();
            Rich(Faction.Elves);
            var builder = elf.GetComponent<Builder>();
            builder.ServerBuild(BuildingKind.ElfHouse, TestArena.Ground(TestArena.Centre + new Vector3(0f, 0f, 80f)).ToCore());
            yield return null;
            Assert.That(Count(BuildingKind.ElfHouse), Is.EqualTo(0), "дом эльфа встал в 80 м от него");
            builder.ServerBuild(BuildingKind.ElfHouse, TestArena.Ground(TestArena.Centre + new Vector3(0f, 0f, 15f)).ToCore());
            yield return null;
            Assert.That(Count(BuildingKind.ElfHouse), Is.EqualTo(1), "дом эльфа не встал рядом с ним");
            builder.ServerBuild(BuildingKind.Storage, TestArena.Ground(TestArena.Centre + new Vector3(30f, 0f, 0f)).ToCore());
            yield return null;
            Assert.That(Count(BuildingKind.Storage), Is.EqualTo(0), "эльф поставил склад — эльфам не строить");
        }

        [UnityTest]
        public IEnumerator DestroyedBuildingDisappears()
        {
            var guard = TestArena.Fighter(Faction.Guard, TestArena.Centre, 0f);
            yield return TestArena.Settle();
            var at = TestArena.Ground(TestArena.Centre + new Vector3(0f, 0f, 20f)).ToCore();
            var barracks = BuildingActor.Spawn(BuildingKind.SwordBarracks, Faction.Villain, at, true, null);
            yield return null;
            barracks.TakeDamage(100000f, "torso", WeaponKind.Hammer, false, guard);
            yield return null;
            Assert.That(barracks == null, Is.True, "разрушенная казарма осталась в мире");
        }
    }
}
