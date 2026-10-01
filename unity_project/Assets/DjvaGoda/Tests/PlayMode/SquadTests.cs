// Проверки личного отряда в живой сцене (без сети). Нанимают только у своей
// казармы, за ресурсы и до вместимости (база плюс дома дружины); строй
// меняется приказом; «туда» — отряд приходит на точку; «с обозом» — бойцы
// встают охраной к своей повозке. Цены и вместимость — Deals ядра.
using System.Collections;
using System.Collections.Generic;
using DjvaGoda.Core;
using DjvaGoda.Game;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace DjvaGoda.Tests
{
    public class SquadTests
    {
        [UnitySetUp]
        public IEnumerator Build() { yield return TestArena.Load(); }

        [UnityTearDown]
        public IEnumerator Clear() { yield return TestArena.Clear(); }

        static PlayerCharacter Guard(out BuildingActor barracks)
        {
            var at = TestArena.Ground(TestArena.Centre).ToCore();
            barracks = BuildingActor.Spawn(BuildingKind.SwordBarracks, Faction.Guard, at + new V3(0f, 0f, 12f), true, null);
            var guard = TestArena.Fighter(Faction.Guard, TestArena.Centre, 0f);
            var wallet = Treasury.Of(Faction.Guard);
            wallet.Carried.Capacity = 5000;
            wallet.Carried.Amounts = new[] { 0, 0, 1000, 1000, 0, 0 };
            return guard;
        }

        [UnityTest]
        public IEnumerator TrainAtBarracksUpToCapacity()
        {
            BuildingActor barracks;
            var guard = Guard(out barracks);
            yield return TestArena.Settle();
            var shop = guard.GetComponent<Shop>();
            int gold = Treasury.Of(Faction.Guard).GetAmount(ResourceKind.Gold);
            shop.Request(DealKind.Train, 0);
            Assert.That(Squads.Of(guard).Count, Is.EqualTo(1), "мечник не нанят");
            Assert.That(Treasury.Of(Faction.Guard).GetAmount(ResourceKind.Gold), Is.EqualTo(gold - Res.At(Res.UnitCost, ResourceKind.Gold)), "цена не списана");
            for (int i = 0; i < Res.SquadBase + 2; i++) shop.Request(DealKind.Train, 0);
            Assert.That(Squads.Of(guard).Count, Is.EqualTo(Res.SquadBase), "нанято сверх вместимости");
            Assert.That(guard.GetComponent<PlayerCombat>().Refusal, Does.Contain("отряд полон"), "отказ на вместимости не объяснён");
            shop.Request(DealKind.Train, 1);
            Assert.That(guard.GetComponent<PlayerCombat>().Refusal, Does.Contain("построй"), "лучник нанят без казармы лучников");

            guard.Teleport(TestArena.Centre + new Vector3(60f, 0f, 0f));
            BuildingActor.Spawn(BuildingKind.House, Faction.Guard, TestArena.Ground(TestArena.Centre).ToCore() + new V3(-30f, 0f, 0f), true, null);
            yield return TestArena.Settle();
            shop.Request(DealKind.Train, 0);
            Assert.That(Squads.Of(guard).Count, Is.EqualTo(Res.SquadBase), "нанят вдали от казармы");
            Assert.That(Squads.Capacity(Faction.Guard), Is.EqualTo(Res.SquadBase + Res.HouseSlots), "дом дружины не добавил мест");
        }

        [UnityTest]
        public IEnumerator FormationMoveAndEscort()
        {
            BuildingActor barracks;
            var guard = Guard(out barracks);
            yield return TestArena.Settle();
            var shop = guard.GetComponent<Shop>();
            shop.Request(DealKind.Train, 0);
            shop.Request(DealKind.Train, 0);
            var squad = Squads.Of(guard);
            shop.Request(DealKind.Squad, 10 + (int)FormationKind.ShieldWall);
            Assert.That(squad[0].CommanderFormation, Is.EqualTo(FormationKind.ShieldWall), "строй не сменён");

            var point = TestArena.Ground(TestArena.Centre + new Vector3(-20f, 0f, -15f)).ToCore();
            Squads.Move(guard, point);
            float t = 0f;
            while (t < 25f && (squad[0].At.FlatDistance(point) > 8f || squad[1].At.FlatDistance(point) > 8f))
            {
                t += Time.deltaTime;
                yield return null;
            }
            Assert.That(squad[0].At.FlatDistance(point), Is.LessThan(8f), "отряд не пришёл на точку; он в " + squad[0].At);

            var at = TestArena.Ground(TestArena.Centre).ToCore();
            var cart = CaravanActor.Spawn(Faction.Guard, 0, new List<V3> { at, at + new V3(0f, 0f, 60f) }, 1,
                Object.FindAnyObjectByType<World>(), Treasury.Of(Faction.Guard), null);
            shop.Request(DealKind.Squad, 1);
            Assert.That(squad[0].Escort, Is.EqualTo(cart), "отряд не приставлен к повозке");
            shop.Request(DealKind.Squad, 0);
            Assert.That(squad[0].Escort, Is.Null, "«ко мне» не снял охрану");
            Assert.That(guard.SquadHold, Is.False, "«ко мне» не вернул отряд к командиру");
        }
    }
}
