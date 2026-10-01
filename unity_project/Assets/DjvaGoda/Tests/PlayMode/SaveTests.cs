// Проверки шага 9, часть «в»: сохранение мира в живой сцене (без сети, во
// временный каталог). Записали — новая сцена — подняли: постройка с ходом
// стройки и ступенью, казна стороны, исход партии; человеку по профилю и
// стороне вернулись раны, протезы, трофеи и служба, а за другую сторону —
// ничего. Схема — SaveData ядра.
using System.Collections;
using System.IO;
using DjvaGoda.Core;
using DjvaGoda.Game;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace DjvaGoda.Tests
{
    public class SaveTests
    {
        string _folder;

        [UnitySetUp]
        public IEnumerator Build()
        {
            _folder = Path.Combine(Application.temporaryCachePath, "проверка-сохранений");
            if (Directory.Exists(_folder)) Directory.Delete(_folder, true);
            yield return TestArena.Load();
        }

        [UnityTearDown]
        public IEnumerator Clear()
        {
            yield return TestArena.Clear();
            if (Directory.Exists(_folder)) Directory.Delete(_folder, true);
        }

        SaveGame Open()
        {
            var save = SaveGame.Instance;
            Assert.That(save, Is.Not.Null, "SaveGame нет");
            save.Frozen = false;
            save.Folder = _folder;
            save.WorldId = "проверка";
            return save;
        }

        [UnityTest]
        public IEnumerator SaveAndLoadWorldAndPlayer()
        {
            var save = Open();
            var fort = Factions.Spawn[(int)Faction.Villain];
            var farm = BuildingActor.Spawn(BuildingKind.Farm, Faction.Villain, fort + new V3(-25f, 0f, 0f), false, null);
            farm.State.Progress = 0.4f;
            Treasury.Of(Faction.Villain).Stored.Capacity = 300;
            Treasury.Of(Faction.Villain).Stored.Amounts = new[] { 11, 22, 33, 44, 0, 0 };
            MatchGoals.Instance.State.LeaderDown[(int)Faction.Guard] = true;

            var guard = TestArena.Fighter(Faction.Guard, TestArena.Centre, 0f);
            guard.Profile = "тестер";
            guard.Body.RegisterHit("arm_l", 100f, WeaponKind.Sword);
            guard.Body.GrantProsthetic(Limb.ArmL, 2);
            guard.Trophies[(int)TrophyKind.Legs] = 4;
            guard.Service.OrdersDone = 3;
            guard.Kit.ArmorTier = 2;
            yield return TestArena.Settle();
            Assert.That(save.Save(), Is.Not.Empty, "сохранение не записано");
            Assert.That(File.Exists(save.PathOf), Is.True, "файла нет");

            yield return TestArena.Load();
            save = Open();
            Assert.That(save.LoadWorld(), Is.True, "сохранение не поднято");
            BuildingActor restored = null;
            foreach (var b in Object.FindObjectsByType<BuildingActor>(FindObjectsSortMode.None))
                if (b.State.Kind == BuildingKind.Farm && b.Side == (int)Faction.Villain) restored = b;
            Assert.That(restored, Is.Not.Null, "поле не вернулось");
            Assert.That(restored.State.Progress, Is.EqualTo(0.4f).Within(0.01f), "ход стройки не вернулся");
            Assert.That(Treasury.Of(Faction.Villain).GetAmount(ResourceKind.Iron), Is.EqualTo(44), "склад злодея не вернулся");
            Assert.That(MatchGoals.Instance.State.LeaderDown[(int)Faction.Guard], Is.True, "исход партии не вернулся");

            var again = TestArena.Fighter(Faction.Guard, TestArena.Centre, 0f);
            again.Profile = "тестер";
            Assert.That(save.RestorePlayer(again), Is.True, "нажитое не возвращено");
            Assert.That(again.Body.IsSevered(Limb.ArmL), Is.True, "отрубленная рука отросла");
            Assert.That(again.Body.Tier(Limb.ArmL), Is.EqualTo(2), "протез потерян");
            Assert.That(again.Trophies[(int)TrophyKind.Legs], Is.EqualTo(4), "трофеи потеряны");
            Assert.That(again.Service.OrdersDone, Is.EqualTo(3), "служба потеряна");
            Assert.That(again.Kit.ArmorTier, Is.EqualTo(2), "доспех потерян");
            Assert.That(save.RestorePlayer(again), Is.False, "нажитое накатили дважды");

            var other = TestArena.Fighter(Faction.Elves, TestArena.Centre + new Vector3(3f, 0f, 0f), 0f);
            other.Profile = "тестер";
            Assert.That(save.RestorePlayer(other), Is.False, "нажитое стражи досталось эльфу");
        }
    }
}
