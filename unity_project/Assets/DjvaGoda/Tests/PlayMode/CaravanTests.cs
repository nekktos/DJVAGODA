// Проверки шага 6, часть «г»: шахты и обозы в живой сцене. Шахта копит сама
// и быстрее с шахтёром; без склада и без лошадей обоз не уходит; полный рейс —
// от склада к шахте, погрузка, назад, железо на складе, лошади в конюшне.
// Скорости и вместимость — ядро (CoreTests); здесь — что Unity-слой их исполняет.
using System.Collections;
using DjvaGoda.Core;
using DjvaGoda.Game;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace DjvaGoda.Tests
{
    public class CaravanTests
    {
        [UnitySetUp]
        public IEnumerator Build() { yield return TestArena.Load(); }

        [UnityTearDown]
        public IEnumerator Clear() { yield return TestArena.Clear(); }

        static int IronMine()
        {
            for (int i = 0; i < MapLayout.Mines.Length; i++)
                if (MapLayout.Mines[i].Kind == ResourceKind.Iron) return i;
            return 0;
        }

        [UnityTest]
        public IEnumerator MineDigsFasterWithMiner()
        {
            int iron = IronMine();
            var mine = Mines.States[iron];
            mine.Stored = Res.Empty();
            yield return TestArena.Wait(5f);
            int alone = mine.Stored[(int)ResourceKind.Iron];
            Assert.That(alone, Is.GreaterThan(0), "шахта сама не копит");
            mine.Stored = Res.Empty();
            float t = 0f;
            while (t < 5f)
            {
                Mines.Dig(Mines.SiteBase - iron, 77);
                t += Time.deltaTime;
                yield return null;
            }
            Assert.That(mine.Stored[(int)ResourceKind.Iron], Is.GreaterThan(alone), "шахтёр у входа не ускорил шахту");
        }

        [UnityTest]
        public IEnumerator NoStorageOrHorsesNoCaravan()
        {
            var villain = TestArena.Fighter(Faction.Villain, TestArena.Centre, 0f);
            villain.Kit.IsLeader = true;
            yield return TestArena.Settle();
            var builder = villain.GetComponent<Builder>();
            builder.ServerSendCaravan(new V3[0]);
            Assert.That(villain.GetComponent<PlayerCombat>().Refusal, Does.Contain("склад"), "без склада — отказ не объяснён");
            BuildingActor.Spawn(BuildingKind.Storage, Faction.Villain, TestArena.Ground(TestArena.Centre + new Vector3(0f, 0f, 15f)).ToCore(), true, null);
            yield return null;
            Treasury.Of(Faction.Villain).Horses = 0;
            builder.ServerSendCaravan(new V3[0]);
            Assert.That(villain.GetComponent<PlayerCombat>().Refusal, Does.Contain("лошад"), "без лошадей — отказ не объяснён");
            Assert.That(Object.FindObjectsByType<CaravanActor>(FindObjectsSortMode.None).Length, Is.EqualTo(0), "обоз ушёл без лошадей");
        }

        [UnityTest]
        public IEnumerator FullTripBringsIron()
        {
            int iron = IronMine();
            var dock = Mines.Dock(iron);
            var facing = MapLayout.MineFacing(MapLayout.Mines[iron].At);
            var storageAt = TestArena.Ground((dock + facing * 35f).ToUnity()).ToCore();
            var villain = TestArena.Fighter(Faction.Villain, (storageAt + facing * 12f).ToUnity(), 0f);
            villain.Kit.IsLeader = true;
            yield return TestArena.Settle();
            BuildingActor.Spawn(BuildingKind.Storage, Faction.Villain, storageAt, true, null);
            yield return null;
            var wallet = Treasury.Of(Faction.Villain);
            wallet.Horses = 2;
            Mines.States[iron].Stored[(int)ResourceKind.Iron] = 100;
            villain.GetComponent<Builder>().ServerSendCaravan(new V3[0]);
            yield return null;
            Assert.That(Object.FindObjectsByType<CaravanActor>(FindObjectsSortMode.None).Length, Is.EqualTo(1), "обоз не ушёл");
            Assert.That(wallet.HorsesOut, Is.EqualTo(2), "лошади не ушли в упряжку");
            float t = 0f;
            while (t < 60f && Object.FindObjectsByType<CaravanActor>(FindObjectsSortMode.None).Length > 0)
            {
                t += Time.deltaTime;
                yield return null;
            }
            Assert.That(Object.FindObjectsByType<CaravanActor>(FindObjectsSortMode.None).Length, Is.EqualTo(0), "обоз за минуту не вернулся");
            Assert.That(wallet.Stored.GetAmount(ResourceKind.Iron), Is.GreaterThan(0), "железа на складе нет");
            Assert.That(wallet.HorsesOut, Is.EqualTo(0), "лошади не вернулись в конюшню");
            Assert.That(wallet.Horses, Is.EqualTo(2), "лошадей стало меньше без боя");
        }
    }
}
