// Проверки шагов 3 и 5 в живом Unity: мир строится, персонаж стоит на земле,
// ходит, поднимается по пандусу на плато. Повторяют наборы ходьбы
// Godot-версии; правила — в core_tests, здесь — что Unity-слой их не ломает.
using System.Collections;
using DjvaGoda.Core;
using DjvaGoda.Game;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace DjvaGoda.Tests
{
    public class WalkTests
    {
        Bootstrap _boot;

        [UnitySetUp]
        public IEnumerator Build()
        {
            var go = new GameObject("Загрузчик");
            go.SetActive(false);
            _boot = go.AddComponent<Bootstrap>();
            _boot.Side = Faction.Guard;
            go.SetActive(true);
            // Кадр на Awake/Start и физику.
            yield return null;
            yield return new WaitForFixedUpdate();
        }

        [UnityTearDown]
        public IEnumerator Clear()
        {
            foreach (var root in Object.FindObjectsByType<Transform>(FindObjectsSortMode.None))
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
            while (t < 15f && player.Feet.Y < MapLayout.PlateauHeight - 0.5f)
            {
                t += Time.deltaTime;
                yield return null;
            }
            player.Scripted = null;
            Assert.That(player.Feet.Y, Is.GreaterThan(MapLayout.PlateauHeight - 0.5f),
                "по пандусу на плато не поднялся: высота " + player.Feet.Y + " за " + t + " с");
        }
    }
}
