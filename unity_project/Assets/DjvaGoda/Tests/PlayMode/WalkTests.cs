// Проверки шагов 3 и 5 в живом Unity: мир в сцене совпадает с планом, персонаж стоит на земле,
// ходит, поднимается по пандусу на плато. Повторяют наборы ходьбы
// Godot-версии; правила — в EditMode CoreTests, здесь — что Unity-слой их не ломает.
using System.Collections;
using DjvaGoda.Core;
using DjvaGoda.Game;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;

namespace DjvaGoda.Tests
{
    public class WalkTests
    {
        Bootstrap _boot;

        /// Настоящая сцена игры: мир в ней собран в редакторе, а не строится
        /// заново. Она сетевая — персонажа ставим сами, без хоста.
        [UnitySetUp]
        public IEnumerator Build()
        {
            SceneManager.LoadScene("Main");
            // Кадр на загрузку сцены и Awake.
            yield return null;
            _boot = Object.FindAnyObjectByType<Bootstrap>();
            Assert.That(_boot, Is.Not.Null, "в сцене Main нет загрузчика");
            _boot.SpawnLocal(Faction.Guard);
            // Кадр на Start персонажа и физику.
            yield return null;
            yield return new WaitForFixedUpdate();
        }

        [UnityTest]
        public IEnumerator WorldMatchesPlan()
        {
            var world = _boot.World;
            Assert.That(world, Is.Not.Null, "в сцене нет мира");
            Assert.That(world.PlanPrint, Is.EqualTo(World.Print(world.Plan, world.Forest)),
                "мир в сцене собран по старому плану: ДжваГода → Собрать мир");
            Assert.That(world.Trees.Length, Is.EqualTo(world.Forest.Count), "деревьев в сцене не столько, сколько в лесу плана");
            foreach (var tree in world.Trees) Assert.That(tree, Is.Not.Null, "дерево леса потеряно в сцене");
            Assert.That(_boot.Nav.Ready, Is.True, "сетка навигации не запечена");
            yield return null;
        }

        [UnityTearDown]
        public IEnumerator Clear()
        {
            foreach (var root in Object.FindObjectsByType<Transform>())
                if (root != null && root.parent == null) Object.Destroy(root.gameObject);
            yield return null;
        }

        [UnityTest]
        public IEnumerator WorldHasGroundUnderEverySpawn()
        {
            Assert.That(_boot.World.Plan.Pieces.Count, Is.GreaterThan(400), "план мира пуст");
            foreach (var spawn in Factions.Spawn)
            {
                var from = (spawn + new V3(0f, 30f, 0f)).ToUnity();
                RaycastHit hit;
                Assert.That(Physics.Raycast(from, Vector3.down, out hit, 60f), Is.True, "под точкой появления " + spawn + " нет земли");
                Assert.That(Mathf.Abs(hit.point.y - spawn.Y), Is.LessThan(3f), "земля не там: " + hit.point.y + " против " + spawn.Y);
            }
            yield return null;
        }

        [UnityTest]
        public IEnumerator PlayerStandsAndWalksForward()
        {
            var player = _boot.Player;
            player.Yaw = 0f;
            float t = 0f;
            while (t < 1.5f)
            {
                t += Time.deltaTime;
                yield return null;
            }
            var controller = player.GetComponent<CharacterController>();
            Assert.That(controller.isGrounded, Is.True, "персонаж не стоит на земле");
            var start = player.Feet;
            player.Scripted = new MotorInput { MoveY = -1f };
            t = 0f;
            while (t < 2f)
            {
                t += Time.deltaTime;
                yield return null;
            }
            player.Scripted = null;
            var moved = player.Feet - start;
            // «Вперёд» ядра при yaw = 0 — это −Z ядра.
            Assert.That(-moved.Z, Is.GreaterThan(8f), "за 2 с шагом прошёл " + moved);
            Assert.That(Mathf.Abs(moved.X), Is.LessThan(1f), "увело вбок: " + moved);
        }

        [UnityTest]
        public IEnumerator RampLeadsUpToThePlateau()
        {
            var player = _boot.Player;
            var controller = player.GetComponent<CharacterController>();
            // Встать у подножия пандуса лицом к плато (к −Z ядра).
            controller.enabled = false;
            player.transform.position = (MapLayout.RampFoot + new V3(0f, 1f, 8f)).ToUnity();
            controller.enabled = true;
            player.Yaw = 0f;
            player.Scripted = new MotorInput { MoveY = -1f };
            float t = 0f;
            float logged = 0f;
            while (t < 15f && player.Feet.Y < MapLayout.PlateauHeight - 0.5f)
            {
                t += Time.deltaTime;
                if (t - logged > 1f)
                {
                    logged = t;
                    Debug.Log("[пандус] t=" + t.ToString("0.0") + " ноги " + player.Feet + " на земле " + controller.isGrounded
                        + " скорость " + player.Velocity + " dt " + Time.deltaTime);
                }
                yield return null;
            }
            player.Scripted = null;
            Assert.That(player.Feet.Y, Is.GreaterThan(MapLayout.PlateauHeight - 0.5f),
                "по пандусу на плато не поднялся: высота " + player.Feet.Y + " за " + t + " с");
        }

        static float FlatToSegment(V3 p, V3 a, V3 b)
        {
            float dx = b.X - a.X, dz = b.Z - a.Z;
            float len = dx * dx + dz * dz;
            float t = len < 1e-6f ? 0f : Mathf.Clamp01(((p.X - a.X) * dx + (p.Z - a.Z) * dz) / len);
            return p.FlatDistance(new V3(a.X + dx * t, 0f, a.Z + dz * t));
        }

        [UnityTest]
        public IEnumerator PalaceIsReachedOnlyByTheRamp()
        {
            while (!_boot.Nav.Ready) yield return null;
            var guard = Factions.Spawn[(int)Faction.Guard];
            var villain = Factions.Spawn[(int)Faction.Villain];
            var path = _boot.Nav.PathBetween(guard, villain);
            Assert.That(path.Count, Is.GreaterThan(1), "пути со двора стражи к форту злодея нет");
            Assert.That(path[path.Count - 1].FlatDistance(villain), Is.LessThan(15f), "путь обрывается в " + path[path.Count - 1]);
            // Меряем до ОТРЕЗКОВ пути: углы у сетки только на поворотах, и прямой
            // участок через пандус угла у подножия может не иметь.
            float nearRamp = float.MaxValue;
            for (int i = 1; i < path.Count; i++) nearRamp = Mathf.Min(nearRamp, FlatToSegment(MapLayout.RampFoot, path[i - 1], path[i]));
            // Въезд на плато один — пандус; путь со склонов значит дыру в сетке.
            Assert.That(nearRamp, Is.LessThan(MapLayout.RampWidth), "путь с плато идёт не через пандус: ближе всего " + nearRamp + " м");
        }
    }
}
