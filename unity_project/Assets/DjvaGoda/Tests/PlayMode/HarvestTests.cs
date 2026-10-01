// Проверки шага 6, часть «а»: добыча ударом и склад в живой сцене.
// Число ударов, выход за удар и бонус инструмента — правила ядра (CoreTests);
// здесь — что удар находит дерево и камень, ресурс ложится в ношу стороны,
// исчерпанный источник исчезает, а у своего склада ноша переходит в склад.
using System.Collections;
using DjvaGoda.Core;
using DjvaGoda.Game;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace DjvaGoda.Tests
{
    public class HarvestTests
    {
        [UnitySetUp]
        public IEnumerator Build() { yield return TestArena.Load(); }

        [UnityTearDown]
        public IEnumerator Clear() { yield return TestArena.Clear(); }

        /// Встать перед источником в трёх метрах и бить до исчерпания (не больше max ударов).
        static IEnumerator Chop(PlayerCharacter who, WeaponKind weapon, Transform source, int max, System.Action<int> done)
        {
            int hits = 0;
            var combat = who.GetComponent<PlayerCombat>();
            while (source != null && hits < max)
            {
                var aim = (source.position + Vector3.up * 1.5f).ToCore() - Aim.Origin(who.Feet);
                combat.ServerAttack(weapon, Aim.Origin(who.Feet), new V3(aim.X, 0f, aim.Z).Normalized());
                hits++;
                yield return TestArena.Wait(Weapons.Cooldown[(int)weapon] + 0.05f);
            }
            done(hits);
        }

        [UnityTest]
        public IEnumerator SwordFellsForestTree()
        {
            var world = Object.FindAnyObjectByType<World>();
            // Дерево на кромке леса: самое далёкое от поселения — с открытой стороны.
            int index = 0;
            float far = 0f;
            var centre = MapLayout.ZoneCenters[(int)Zone.Elves];
            for (int i = 0; i < world.Forest.Count; i++)
            {
                float d = world.Forest.Positions[i].FlatDistance(centre);
                if (d > far) { far = d; index = i; }
            }
            var tree = world.Trees[index].transform;
            var outward = (tree.position - centre.ToUnity());
            outward.y = 0f;
            var elf = TestArena.Fighter(Faction.Elves, tree.position + outward.normalized * 3f, 0f);
            yield return TestArena.Settle();
            var wallet = Treasury.Of(Faction.Elves);
            int before = wallet.GetAmount(ResourceKind.Wood);
            int hits = 0;
            yield return Chop(elf, WeaponKind.Sword, tree, Res.SourceHits + 2, n => hits = n);
            Assert.That(tree == null, Is.True, "дерево не повалено за " + hits + " ударов");
            Assert.That(hits, Is.EqualTo(Res.SourceHits), "дерево пало не за положенное число ударов");
            Assert.That(world.Forest.IsFelled(index), Is.True, "лес ядра не знает, что дерево повалено");
            int yieldPerHit = MeleeRules.HarvestYield(WeaponKind.Sword, ResourceKind.Wood);
            Assert.That(wallet.GetAmount(ResourceKind.Wood) - before, Is.EqualTo(yieldPerHit * Res.SourceHits), "дерева в ноше не прибавилось");
        }

        [UnityTest]
        public IEnumerator HammerOnRockGivesStone()
        {
            Harvestable rock = null;
            foreach (var h in Object.FindObjectsByType<Harvestable>(FindObjectsSortMode.None))
                if (h.Resource == ResourceKind.Stone && h.TreeIndex < 0 && h.Key >= Harvestable.PlanBase
                    && h.transform.position.ToCore().FlatDistance(new V3(0f, 0f, 0f)) < 120f)
                    rock = h;
            Assert.That(rock, Is.Not.Null, "камня у перекрёстка нет");
            var rockAt = rock.transform.position;
            var villain = TestArena.Fighter(Faction.Villain, rockAt + Vector3.right * 3f, 0f);
            yield return TestArena.Settle();
            var wallet = Treasury.Of(Faction.Villain);
            int before = wallet.GetAmount(ResourceKind.Stone);
            int hits = 0;
            yield return Chop(villain, WeaponKind.Hammer, rock.transform, Res.SourceHits + 2, n => hits = n);
            Assert.That(rock == null, Is.True, "камень не выбит за " + hits + " ударов");
            int perHit = MeleeRules.HarvestYield(WeaponKind.Hammer, ResourceKind.Stone);
            Assert.That(perHit, Is.GreaterThan(Res.YieldPerHit), "у молота нет бонуса по камню");
            Assert.That(wallet.GetAmount(ResourceKind.Stone) - before, Is.EqualTo(perHit * hits), "камня в ноше не столько, сколько ударов");
        }

        [UnityTest]
        public IEnumerator CarriedGoesToOwnStorage()
        {
            var guard = TestArena.Fighter(Faction.Guard, TestArena.Centre, 0f);
            yield return TestArena.Settle();
            var at = TestArena.Ground(TestArena.Centre + new Vector3(10f, 0f, 0f)).ToCore();
            var storage = BuildingActor.Spawn(BuildingKind.Storage, Faction.Guard, at, true, null);
            var wallet = Treasury.Of(Faction.Guard);
            wallet.Stored.Capacity = Res.StorageBonus;
            int carried = wallet.GetAmount(ResourceKind.Wood);
            Assert.That(carried, Is.GreaterThan(0), "у стражи нет стартового дерева");
            yield return TestArena.Wait(Res.DepositInterval + 0.3f);
            Assert.That(wallet.Stored.GetAmount(ResourceKind.Wood), Is.GreaterThan(0), "ноша у своего склада не сдана");
            Assert.That(wallet.Carried.GetAmount(ResourceKind.Wood), Is.LessThan(carried), "при себе не убыло");
            Object.Destroy(storage.gameObject);
        }
    }
}
