// Проверки обучения первых минут в живой сцене (без сети). Шаг засчитывается
// делом и не откатывается; необязательный шаг, который нечем оплатить,
// пропускается сам; до каждой метки каждой цепочки можно дойти по сетке
// навигации от точки своей стороны (метка туда, куда не дойти, — худшая из
// подсказок; так проверял и набор «онбординг» Godot-версии).
using System.Collections;
using DjvaGoda.Core;
using DjvaGoda.Game;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace DjvaGoda.Tests
{
    public class OnboardingTests
    {
        Onboarding _guide;
        CameraRig _rig;

        [UnitySetUp]
        public IEnumerator Build()
        {
            yield return TestArena.Load();
            yield return null;
            _rig = Object.FindAnyObjectByType<CameraRig>();
            _guide = _rig.GetComponent<Onboarding>();
            Assert.That(_guide, Is.Not.Null, "обучения на камере нет");
        }

        [UnityTearDown]
        public IEnumerator Clear()
        {
            GameMode.Strategy = false;
            yield return TestArena.Clear();
        }

        [UnityTest]
        public IEnumerator VillainStepsAdvanceByDeeds()
        {
            var fort = Factions.Spawn[(int)Faction.Villain].ToUnity();
            var villain = TestArena.Fighter(Faction.Villain, fort, 0f);
            villain.Kit.IsLeader = true;
            _rig.Target = villain;
            Treasury.Of(Faction.Villain).Carried.Amounts = Res.Empty();
            yield return TestArena.Settle();
            Assert.That(_guide.Passed, Is.EqualTo(0), "начали не с первого шага");
            Assert.That(_guide.CurrentText, Does.Contain("Осмотрись"));

            villain.Teleport(fort + new Vector3(50f, 0f, 0f));
            yield return TestArena.Settle();
            Assert.That(_guide.Passed, Is.EqualTo(1), "отход от точки появления не засчитан");

            var wallet = Treasury.Of(Faction.Villain);
            wallet.Carried.Capacity = 5000;
            wallet.Carried.Amounts = new[] { 500, 500, 500, 0, 0, 0 };
            yield return null;
            Assert.That(_guide.Passed, Is.EqualTo(2), "набранное на склад не засчитано");
            GameMode.Strategy = true;
            yield return null;
            GameMode.Strategy = false;
            yield return null;
            Assert.That(_guide.Passed, Is.EqualTo(3), "вид сверху не засчитан");
            Assert.That(_guide.CurrentPlace.HasValue, Is.True, "у шага «склад» нет места");

            // Пройденное не откатывается: деньги ушли — шаг «набери» не возвращается.
            wallet.Carried.Amounts = Res.Empty();
            yield return null;
            Assert.That(_guide.Passed, Is.EqualTo(3), "шаг откатился назад");
        }

        [UnityTest]
        public IEnumerator EveryPlaceIsReachable()
        {
            var villain = TestArena.Fighter(Faction.Villain, TestArena.Centre, 0f);
            _rig.Target = villain;
            yield return TestArena.Settle();
            var nav = Object.FindAnyObjectByType<NavWorld>();
            var problems = "";
            for (int side = 0; side < Factions.Count; side++)
            {
                foreach (var place in _guide.Places((Faction)side))
                {
                    // Ближайшая к месту точка сетки бывает на крыше прилавка: судим
                    // по концу пути у земли — в шести метрах от места хватает.
                    var path = nav.PathBetween(Factions.Spawn[side], place);
                    var end = path.Count > 0 ? path[path.Count - 1] : Factions.Spawn[side];
                    if (end.FlatDistance(place) > 6f)
                        problems += Factions.Names[side] + ": " + place + " (путь кончается в " + end + "); ";
                }
            }
            Assert.That(problems, Is.Empty, "недостижимые метки: " + problems);
        }
    }
}
