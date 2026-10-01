// Проверки езды верхом и действий с чужим обозом в живой сцене (без сети).
// Эльф у вставшего обоза злодея уводит лошадей — они встают рядом живыми,
// из конюшни злодея ушли, засада засчитана; на лошадь садятся и спешиваются
// одной клавишей. Обоз без лошадей грабят — груз кучей на землю. Страж со
// своим складом перехватывает обоз — тот едет к нему, лошади тоже его.
// Правило «что можно сделать» — CaravanRules.ActionFor ядра.
using System.Collections;
using System.Collections.Generic;
using DjvaGoda.Core;
using DjvaGoda.Game;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace DjvaGoda.Tests
{
    public class RideTests
    {
        [UnitySetUp]
        public IEnumerator Build() { yield return TestArena.Load(); }

        [UnityTearDown]
        public IEnumerator Clear() { yield return TestArena.Clear(); }

        static CaravanActor Cart(Faction side, int horses)
        {
            var at = TestArena.Ground(TestArena.Centre).ToCore();
            var wallet = Treasury.Of(side);
            wallet.Horses = horses;
            wallet.HorsesOut = horses;
            var route = new List<V3> { at, at + new V3(0f, 0f, 40f), at + new V3(0f, 0f, 80f) };
            return CaravanActor.Spawn(side, 0, route, horses, Object.FindAnyObjectByType<World>(), wallet, null);
        }

        [UnityTest]
        public IEnumerator ElfRobsHorsesAndRides()
        {
            var cart = Cart(Faction.Villain, 2);
            var elf = TestArena.Fighter(Faction.Elves, TestArena.Centre + new Vector3(3f, 0f, 0f), 0f);
            elf.Tasks.Task = ElfTaskKind.Ambush;
            yield return TestArena.Wait(0.3f);
            Assert.That(cart.HaltedNow, Is.True, "обоз не встал рядом с эльфом");
            var shop = elf.GetComponent<Shop>();
            shop.ServerDeal(DealKind.Caravan, 0);
            Assert.That(cart.HorsesNow, Is.EqualTo(0), "лошади остались в упряжке");
            Assert.That(HorseActor.Horses.Count, Is.EqualTo(2), "уведённые лошади не встали рядом");
            Assert.That(Treasury.Of(Faction.Villain).Horses, Is.EqualTo(0), "лошади всё ещё числятся у злодея");
            Assert.That(elf.Tasks.Done, Is.True, "засада не засчитана");

            var horse = HorseActor.Near(elf.Feet);
            Assert.That(horse, Is.Not.Null, "лошадь не в досягаемости");
            shop.ServerDeal(DealKind.Mount, 0);
            Assert.That(elf.Mounted, Is.True, "не сел верхом");
            Assert.That(elf.Horse.Ridden, Is.True, "лошадь под седлом не спрятана");
            yield return null;
            shop.ServerDeal(DealKind.Mount, 0);
            Assert.That(elf.Mounted, Is.False, "не спешился");
            Assert.That(HorseActor.Near(elf.Feet), Is.Not.Null, "лошадь не осталась рядом после спешивания");
        }

        [UnityTest]
        public IEnumerator PlunderSpillsCargo()
        {
            var cart = Cart(Faction.Guard, 0);
            cart.Trip.Cargo = new[] { 0, 0, 30, 15, 0, 0 };
            // Упряжку выбили: рейс без лошадей не выходит, поэтому — после выезда.
            cart.Trip.Horses = 0;
            cart.Trip.HorsePool = 0f;
            var villain = TestArena.Fighter(Faction.Villain, TestArena.Centre + new Vector3(3f, 0f, 0f), 0f);
            yield return TestArena.Wait(0.3f);
            villain.GetComponent<Shop>().ServerDeal(DealKind.Caravan, 0);
            yield return null;
            Assert.That(cart == null || !cart.Alive, Is.True, "разграбленный обоз цел");
            Assert.That(Pickup.All.Count, Is.EqualTo(1), "груз не высыпан");
            Assert.That(Pickup.All[0].Pile.Contents[(int)ResourceKind.Gold], Is.EqualTo(30), "в куче не тот груз");
        }

        [UnityTest]
        public IEnumerator GuardInterceptsVillainCart()
        {
            BuildingActor.Spawn(BuildingKind.Storage, Faction.Guard, TestArena.Ground(TestArena.Centre).ToCore() + new V3(40f, 0f, 0f), true, null);
            var cart = Cart(Faction.Villain, 2);
            var guard = TestArena.Fighter(Faction.Guard, TestArena.Centre + new Vector3(3f, 0f, 0f), 0f);
            guard.Service.Order = OrderKind.Intercept;
            Treasury.Of(Faction.Guard).Horses = 0;
            Treasury.Of(Faction.Guard).HorsesOut = 0;
            yield return TestArena.Wait(0.3f);
            guard.GetComponent<Shop>().ServerDeal(DealKind.Caravan, 0);
            Assert.That(cart.Side, Is.EqualTo((int)Faction.Guard), "обоз не перехвачен");
            Assert.That(cart.Trip.State, Is.EqualTo(CaravanState.ToHome), "перехваченный обоз не едет на склад");
            Assert.That(Treasury.Of(Faction.Guard).Horses, Is.EqualTo(2), "лошади упряжки не перешли к страже");
            Assert.That(Treasury.Of(Faction.Villain).Horses, Is.EqualTo(0), "лошади остались у злодея");
            Assert.That(guard.Service.Done, Is.True, "перехват не засчитан приказом");
        }
    }
}
