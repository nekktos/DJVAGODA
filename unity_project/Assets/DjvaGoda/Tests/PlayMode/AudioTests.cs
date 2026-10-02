// Звук: события мира доходят до Sfx на каждом пире без своих RPC — удар,
// смерть, выстрел и разрыв огненного шара, достройка. Сами клипы — синтез
// (Synth); здесь проверяется только, что нужный звук сыгран.
using System.Collections;
using DjvaGoda.Core;
using DjvaGoda.Game;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace DjvaGoda.Tests
{
    public class AudioTests
    {
        [UnitySetUp]
        public IEnumerator Build()
        {
            yield return TestArena.Load();
            // Уши — к месту боя: дальше слышимости звук не играется.
            var ears = Sfx.Ears();
            Assert.That(ears, Is.Not.Null, "нет слушателя");
            ears.position = TestArena.Centre + Vector3.up * 3f;
        }

        [UnityTearDown]
        public IEnumerator Clear() { yield return TestArena.Clear(); }

        [UnityTest]
        public IEnumerator HitAndDeathSound()
        {
            var victim = TestArena.Fighter(Faction.Elves, TestArena.Centre, 0f);
            var hitter = TestArena.Fighter(Faction.Villain, TestArena.Centre + new Vector3(1.5f, 0f, 0f), 0f);
            yield return TestArena.Settle();
            Actor.Strike(victim, 10f, "torso", WeaponKind.Sword, false, hitter);
            yield return null;
            yield return null;
            Assert.That(Sfx.Last, Is.EqualTo(SoundKind.HitFlesh), "удар не прозвучал");
            Actor.Strike(victim, 5000f, "torso", WeaponKind.Sword, false, hitter);
            yield return null;
            yield return null;
            Assert.That(Sfx.Last, Is.EqualTo(SoundKind.Death), "смерть не прозвучала");
        }

        [UnityTest]
        public IEnumerator FireballCastsAndBursts()
        {
            var caster = TestArena.Fighter(Faction.Villain, TestArena.Centre - new Vector3(0f, 0f, 15f), 0f);
            yield return TestArena.Settle();
            int before = Sfx.Played;
            var origin = (TestArena.Centre + Vector3.up * 1.5f).ToCore();
            Shot.Fire(WeaponKind.Spell, origin, new Vector3(0f, -0.3f, 1f).normalized.ToCore(), caster, 0);
            Assert.That(Sfx.Last, Is.EqualTo(SoundKind.Fireball), "бросок не прозвучал");
            yield return TestArena.Wait(3f);
            Assert.That(Sfx.Last, Is.EqualTo(SoundKind.Explosion), "разрыв не прозвучал");
            Assert.That(Sfx.Played, Is.GreaterThanOrEqualTo(before + 2));
        }

        [UnityTest]
        public IEnumerator FarSoundIsSkipped()
        {
            yield return null;
            int before = Sfx.Played;
            Sfx.Play(SoundKind.HitStone, TestArena.Centre + new Vector3(500f, 0f, 0f));
            Assert.That(Sfx.Played, Is.EqualTo(before), "звук за пределом слышимости сыгран");
            Sfx.Play(SoundKind.HitStone, TestArena.Centre);
            Assert.That(Sfx.Played, Is.EqualTo(before + 1), "звук рядом не сыгран");
        }
    }
}
