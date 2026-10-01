// Проверки шага 6, часть «г»: батраки в живой сцене. Злодей нанимает — цена
// списана, батрак-лесоруб стоит у точки стороны; потолок — отказ; перевод роли
// берёт одного с самого многолюдного дела; лесоруб сам рубит рощу у форта.
// Мозг батрака и цены — ядро (CoreTests); здесь — что Unity-слой их исполняет.
using System.Collections;
using DjvaGoda.Core;
using DjvaGoda.Game;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace DjvaGoda.Tests
{
    public class LabourTests
    {
        [UnitySetUp]
        public IEnumerator Build() { yield return TestArena.Load(); }

        [UnityTearDown]
        public IEnumerator Clear() { yield return TestArena.Clear(); }

        static PlayerCharacter Villain()
        {
            var fort = Factions.Spawn[(int)Faction.Villain].ToUnity();
            var villain = TestArena.Fighter(Faction.Villain, fort, 0f);
            villain.Kit.IsLeader = true;
            var wallet = Treasury.Of(Faction.Villain);
            wallet.Carried.Capacity = 5000;
            wallet.Carried.Amounts = new[] { 0, 0, 2000, 0, 0, 0 };
            return villain;
        }

        [UnityTest]
        public IEnumerator HireUpToLimitAndReassign()
        {
            var villain = Villain();
            yield return TestArena.Settle();
            var builder = villain.GetComponent<Builder>();
            int gold = Treasury.Of(Faction.Villain).GetAmount(ResourceKind.Gold);
            builder.ServerLabour(-1);
            yield return null;
            var crew = Builder.Crew(Faction.Villain);
            Assert.That(crew.Count, Is.EqualTo(1), "батрак не нанят");
            Assert.That(crew[0].Brain.Role, Is.EqualTo(LabourerRole.Lumberjack), "новый батрак — не лесоруб");
            Assert.That(Treasury.Of(Faction.Villain).GetAmount(ResourceKind.Gold),
                Is.EqualTo(gold - Res.At(Res.LabourerCost, ResourceKind.Gold)), "золото за батрака не списано");

            for (int i = 1; i < Res.LabourerLimit + 1; i++) builder.ServerLabour(-1);
            yield return null;
            Assert.That(Builder.Crew(Faction.Villain).Count, Is.EqualTo(Res.LabourerLimit), "нанято больше потолка");
            Assert.That(villain.GetComponent<PlayerCombat>().Refusal, Does.Contain("потолок"), "отказ на потолке не объяснён");

            builder.ServerLabour((int)LabourerRole.Miner);
            int miners = 0;
            foreach (var worker in Builder.Crew(Faction.Villain)) if (worker.Brain.Role == LabourerRole.Miner) miners++;
            Assert.That(miners, Is.EqualTo(1), "перевод роли — не ровно один батрак");
        }

        static LabourerAgent HireAs(PlayerCharacter villain, LabourerRole role)
        {
            var builder = villain.GetComponent<Builder>();
            builder.ServerLabour(-1);
            builder.ServerLabour((int)role);
            return Builder.Crew(Faction.Villain)[0];
        }

        [UnityTest]
        public IEnumerator BuilderJoinsConstruction()
        {
            var villain = Villain();
            yield return TestArena.Settle();
            Treasury.Of(Faction.Villain).Carried.Amounts = new[] { 2000, 2000, 2000, 2000, 0, 0 };
            var fort = Factions.Spawn[(int)Faction.Villain];
            villain.GetComponent<Builder>().ServerBuild(BuildingKind.Storage, fort + new V3(25f, 0f, 0f));
            yield return null;
            BuildingActor storage = null;
            foreach (var b in Object.FindObjectsByType<BuildingActor>(FindObjectsSortMode.None)) storage = b;
            Assert.That(storage, Is.Not.Null, "склад не поставлен");
            var worker = HireAs(villain, LabourerRole.Builder);
            Assert.That(worker.Brain.Role, Is.EqualTo(LabourerRole.Builder));
            float t = 0f;
            while (t < 40f && storage.BuildersNow == 0 && !storage.State.Done)
            {
                t += Time.deltaTime;
                yield return null;
            }
            Assert.That(storage.BuildersNow, Is.GreaterThan(0), "строитель за 40 с не взялся за стройку; он в " + worker.At);
        }

        [UnityTest]
        public IEnumerator FarmerCarriesFood()
        {
            var villain = Villain();
            yield return TestArena.Settle();
            var fort = Factions.Spawn[(int)Faction.Villain];
            var farm = BuildingActor.Spawn(BuildingKind.Farm, Faction.Villain, fort + new V3(-25f, 0f, 0f), true, null);
            farm.State.Grown[(int)ResourceKind.Food] = 40;
            var worker = HireAs(villain, LabourerRole.Farmer);
            float t = 0f;
            while (t < 40f && worker.Brain.Carrying == 0 && Treasury.Of(Faction.Villain).GetAmount(ResourceKind.Food) == 0)
            {
                t += Time.deltaTime;
                yield return null;
            }
            Assert.That(worker.Brain.Carrying > 0 || Treasury.Of(Faction.Villain).GetAmount(ResourceKind.Food) > 0, Is.True,
                "фермер за 40 с не взял еды с поля; он в " + worker.At);
        }

        [UnityTest]
        public IEnumerator LumberjackChopsGrove()
        {
            var villain = Villain();
            yield return TestArena.Settle();
            villain.GetComponent<Builder>().ServerLabour(-1);
            yield return null;
            var worker = Builder.Crew(Faction.Villain)[0];
            int wood = Treasury.Of(Faction.Villain).GetAmount(ResourceKind.Wood);
            float t = 0f;
            while (t < 60f && worker != null && worker.Brain.Carrying == 0
                && Treasury.Of(Faction.Villain).GetAmount(ResourceKind.Wood) == wood)
            {
                t += Time.deltaTime;
                yield return null;
            }
            Assert.That(worker != null, Is.True, "батрак пропал");
            Assert.That(worker.Brain.Carrying > 0 || Treasury.Of(Faction.Villain).GetAmount(ResourceKind.Wood) > wood, Is.True,
                "лесоруб за минуту не нарубил ничего; он в " + worker.At);
        }
    }
}
