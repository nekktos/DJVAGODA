// Проверки шага 4 «Бой» в живой сцене: удар по зонам попадания в дуге,
// стрела в полёте, взрыв огненного шара, молот сбивает, павший лежит.
// Числа — правила ядра (CoreTests); здесь — что Unity-слой их исполняет:
// зоны на месте, сфера удара и снаряд находят их, урон доходит до цели.
using System.Collections;
using DjvaGoda.Core;
using DjvaGoda.Game;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;

namespace DjvaGoda.Tests
{
    public class CombatTests
    {
        /// Ровное место — дорога вдоль x у перекрёстка, вдали от построек.
        static readonly Vector3 Arena = new Vector3(140f, 0f, 0f);

        Bootstrap _boot;

        [UnitySetUp]
        public IEnumerator Build()
        {
            SceneManager.LoadScene("Main");
            yield return null;
            _boot = Object.FindAnyObjectByType<Bootstrap>();
        }

        [UnityTearDown]
        public IEnumerator Clear()
        {
            foreach (var root in Object.FindObjectsByType<Transform>(FindObjectsSortMode.None))
                if (root != null && root.parent == null) Object.Destroy(root.gameObject);
            yield return null;
        }

        static Vector3 Ground(Vector3 at)
        {
            RaycastHit hit;
            if (Physics.Raycast(at + Vector3.up * 50f, Vector3.down, out hit, 100f, HitZone.WorldMask, QueryTriggerInteraction.Ignore))
                return hit.point;
            return at;
        }

        /// Боец без управления: стоит, получает удары.
        static PlayerCharacter Fighter(Faction side, Vector3 at, float yaw)
        {
            var root = new GameObject("Боец " + side);
            root.transform.position = Ground(at) + Vector3.up * 0.05f;
            Bootstrap.AddBody(root.transform, side);
            var character = root.AddComponent<PlayerCharacter>();
            character.Faction = side;
            character.LocalControl = false;
            character.Yaw = yaw;
            root.transform.rotation = CoreSpace.YawToRotation(yaw);
            root.AddComponent<PlayerCombat>();
            return character;
        }

        static IEnumerator Settle()
        {
            yield return null;
            yield return new WaitForFixedUpdate();
            yield return null;
        }

        static V3 AimAt(PlayerCharacter from, PlayerCharacter to, float height)
        {
            return (to.Feet + new V3(0f, height, 0f) - Aim.Origin(from.Feet)).Normalized();
        }

        [UnityTest]
        public IEnumerator SwordHitsInFrontNotBehind()
        {
            var guard = Fighter(Faction.Guard, Arena, 0f);
            var front = Fighter(Faction.Villain, Arena + new Vector3(0f, 0f, 1.8f), Mathf.PI);
            var back = Fighter(Faction.Villain, Arena + new Vector3(0f, 0f, -1.8f), 0f);
            yield return Settle();
            var combat = guard.GetComponent<PlayerCombat>();
            combat.ServerAttack(WeaponKind.Sword, Aim.Origin(guard.Feet), AimAt(guard, front, 1.1f));
            yield return null;
            Assert.That(front.Vitals.Health, Is.LessThan(Vitals.BaseHealth), "меч не задел цель перед собой");
            Assert.That(back.Vitals.Health, Is.EqualTo(Vitals.BaseHealth), "меч задел того, кто за спиной");
            // Одна зона на цель: урон — одного удара (без доспеха ×1, зона ≤ ×2).
            Assert.That(Vitals.BaseHealth - front.Vitals.Health, Is.LessThanOrEqualTo(Weapons.Damage[(int)WeaponKind.Sword] * 2f + 0.01f));
        }

        [UnityTest]
        public IEnumerator ArrowFliesAndHits()
        {
            var guard = Fighter(Faction.Guard, Arena, 0f);
            var target = Fighter(Faction.Villain, Arena + new Vector3(0f, 0f, 20f), Mathf.PI);
            yield return Settle();
            int arrows = guard.Kit.Arrows;
            guard.GetComponent<PlayerCombat>().ServerAttack(WeaponKind.Bow, Aim.Origin(guard.Feet), AimAt(guard, target, 1.1f));
            Assert.That(guard.Kit.Arrows, Is.EqualTo(arrows - 1), "стрела не снята из колчана");
            Assert.That(target.Vitals.Health, Is.EqualTo(Vitals.BaseHealth), "стрела попала мгновенно — без полёта");
            float t = 0f;
            while (t < 1.5f && target.Vitals.Health >= Vitals.BaseHealth)
            {
                t += Time.deltaTime;
                yield return null;
            }
            Assert.That(target.Vitals.Health, Is.LessThan(Vitals.BaseHealth), "стрела за 1.5 с не долетела до цели в 20 м");
            Assert.That(Object.FindObjectsByType<Shot>(FindObjectsSortMode.None).Length, Is.EqualTo(0), "попавшая стрела осталась в мире");
        }

        [UnityTest]
        public IEnumerator FireballBlastsAround()
        {
            var villain = Fighter(Faction.Villain, Arena, 0f);
            var a = Fighter(Faction.Guard, Arena + new Vector3(-1.5f, 0f, 14f), Mathf.PI);
            var b = Fighter(Faction.Guard, Arena + new Vector3(1.5f, 0f, 14f), Mathf.PI);
            yield return Settle();
            // Цель — земля между двумя: прямого попадания нет, только взрыв.
            var ground = Ground(Arena + new Vector3(0f, 0f, 14f)).ToCore();
            var dir = (ground - Aim.Origin(villain.Feet)).Normalized();
            villain.GetComponent<PlayerCombat>().ServerAttack(WeaponKind.Spell, Aim.Origin(villain.Feet), dir);
            float t = 0f;
            while (t < 2f && Object.FindObjectsByType<Shot>(FindObjectsSortMode.None).Length > 0)
            {
                t += Time.deltaTime;
                yield return null;
            }
            Assert.That(a.Vitals.Health, Is.LessThan(Vitals.BaseHealth), "взрыв не задел стоящего слева");
            Assert.That(b.Vitals.Health, Is.LessThan(Vitals.BaseHealth), "взрыв не задел стоящего справа");
        }

        [UnityTest]
        public IEnumerator HammerStaggersAndKillLaysDown()
        {
            var villain = Fighter(Faction.Villain, Arena, 0f);
            var guard = Fighter(Faction.Guard, Arena + new Vector3(0f, 0f, 1.8f), Mathf.PI);
            yield return Settle();
            villain.GetComponent<PlayerCombat>().ServerAttack(WeaponKind.Hammer, Aim.Origin(villain.Feet), AimAt(villain, guard, 1.1f));
            yield return null;
            Assert.That(guard.GetComponent<PlayerCombat>().Stagger, Is.GreaterThan(0f), "молот не сбил с ног");

            guard.TakeDamage(1000f, "torso", WeaponKind.Sword, false, villain);
            yield return null;
            Assert.That(guard.Alive, Is.False, "1000 урона — а жив");
            var body = guard.transform.Find("Тело");
            Assert.That(Vector3.Angle(body.up, Vector3.up), Is.GreaterThan(60f), "павший стоит, а должен лежать");
        }
    }
}
