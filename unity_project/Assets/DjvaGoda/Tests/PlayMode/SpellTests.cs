// Проверки заклинаний в живой сцене (шаг 4): лечение, паралич с кастом и его
// срыв ударом, увядание и слепота, призыв стаи белок по прокачке магии, мана.
// Правила — в ядре (CoreTests); здесь — что Unity-слой исполняет их у хоста:
// находит своих и чужих рядом, платит только за сработавшее.
using System.Collections;
using DjvaGoda.Core;
using DjvaGoda.Game;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

namespace DjvaGoda.Tests
{
    public class SpellTests
    {
        static readonly Vector3 Arena = TestArena.Centre;

        [UnitySetUp]
        public IEnumerator Build() { yield return TestArena.Load(); }

        [UnityTearDown]
        public IEnumerator Clear() { yield return TestArena.Clear(); }

        static PlayerSpells SpellsOf(PlayerCharacter c) { return c.GetComponent<PlayerSpells>(); }

        [UnityTest]
        public IEnumerator HealRestoresAllyAndPaysMana()
        {
            var druid = TestArena.Fighter(Faction.Elves, Arena, 0f);
            var ally = TestArena.Fighter(Faction.Elves, Arena + new Vector3(5f, 0f, 0f), 0f);
            yield return TestArena.Settle();
            ally.Vitals.Health = 40f;
            ally.Body.StartBleeding();
            float mana = druid.Vitals.Mana;
            SpellsOf(druid).ServerCast(AbilityKind.Heal);
            Assert.That(ally.Vitals.Health, Is.EqualTo(40f + Abilities.HealAmount).Within(0.01f), "своему рядом не прибавилось здоровья");
            Assert.That(ally.Body.Bleeding, Is.False, "кровотечение не остановлено");
            Assert.That(druid.Vitals.Mana, Is.EqualTo(mana - Abilities.ManaCost[(int)AbilityKind.Heal]).Within(0.5f), "мана не списана");
            Assert.That(druid.Spells.Ready(AbilityKind.Heal), Is.False, "откат не встал");
        }

        [UnityTest]
        public IEnumerator NoManaNoSpell()
        {
            var druid = TestArena.Fighter(Faction.Elves, Arena, 0f);
            yield return TestArena.Settle();
            druid.Vitals.Mana = 10f;
            druid.Vitals.Health = 50f;
            SpellsOf(druid).ServerCast(AbilityKind.Heal);
            Assert.That(druid.Vitals.Health, Is.EqualTo(50f), "без маны вылечило");
            Assert.That(druid.Spells.Ready(AbilityKind.Heal), Is.True, "без маны встал откат");
            Assert.That(druid.GetComponent<PlayerCombat>().Refusal, Does.Contain("маны"), "отказ не объяснён");
        }

        [UnityTest]
        public IEnumerator ParalysisAfterCastAndHitBreaksCast()
        {
            var villain = TestArena.Fighter(Faction.Villain, Arena, 0f);
            var guard = TestArena.Fighter(Faction.Guard, Arena + new Vector3(0f, 0f, 10f), Mathf.PI);
            yield return TestArena.Settle();
            float mana = villain.Vitals.Mana;
            SpellsOf(villain).ServerCast(AbilityKind.Paralysis);
            Assert.That(villain.Spells.Casting, Is.True, "паралич сработал сразу — без каста");
            Assert.That(guard.Spells.Paralysis, Is.EqualTo(0f), "паралич лёг до конца каста");
            yield return TestArena.Wait(Abilities.ParalysisCast + 0.3f);
            Assert.That(guard.Spells.Paralysis, Is.GreaterThan(0f), "после каста паралича нет");
            Assert.That(villain.Vitals.Mana, Is.LessThan(mana - Abilities.ManaCost[(int)AbilityKind.Paralysis] + 3f), "мана за паралич не списана");

            // Второй злодей: удар по нему во время каста — каст сорван, мана цела.
            var other = TestArena.Fighter(Faction.Villain, Arena + new Vector3(4f, 0f, 0f), 0f);
            yield return TestArena.Settle();
            float before = other.Vitals.Mana;
            SpellsOf(other).ServerCast(AbilityKind.Paralysis);
            other.TakeDamage(5f, "torso", WeaponKind.Sword, false, guard);
            Assert.That(other.Spells.Casting, Is.False, "удар не сорвал каст");
            yield return TestArena.Wait(Abilities.ParalysisCast + 0.3f);
            Assert.That(other.Vitals.Mana, Is.GreaterThanOrEqualTo(before), "сорванный каст стоил маны");
            Assert.That(other.Spells.Ready(AbilityKind.Paralysis), Is.True, "сорванный каст поставил откат");
        }

        [UnityTest]
        public IEnumerator WitherAndBlindLandOnNearestEnemy()
        {
            var villain = TestArena.Fighter(Faction.Villain, Arena, 0f);
            var guard = TestArena.Fighter(Faction.Guard, Arena + new Vector3(0f, 0f, 8f), Mathf.PI);
            yield return TestArena.Settle();
            SpellsOf(villain).ServerCast(AbilityKind.Wither);
            Assert.That(guard.Spells.Wither, Is.GreaterThan(0f), "увядания нет");
            Assert.That(guard.Body.Bleeding, Is.True, "увядание не пустило кровь");
            SpellsOf(villain).ServerCast(AbilityKind.Blind);
            Assert.That(guard.Spells.Blind, Is.GreaterThan(0f), "слепоты нет");
        }

        [UnityTest]
        public IEnumerator SummonSquirrelSwarmBySkill()
        {
            var druid = TestArena.Fighter(Faction.Elves, Arena, 0f);
            yield return TestArena.Settle();
            var spells = SpellsOf(druid);
            System.Func<int> squirrels = () =>
            {
                int n = 0;
                foreach (var unit in Object.FindObjectsByType<UnitAgent>(FindObjectsSortMode.None))
                    if (unit.Brain != null && unit.Brain.Kind == UnitKind.Beast && unit.Side == (int)Faction.Elves && unit.Alive) n++;
                return n;
            };
            druid.Vitals.Mana = druid.Vitals.MaxMana;
            spells.ServerCast(AbilityKind.Summon);
            yield return null;
            Assert.That(squirrels(), Is.EqualTo(Abilities.SwarmMin), "без прокачки заклинания стая не из трёх");
            Assert.That(Object.FindAnyObjectByType<Beast>().name, Is.EqualTo("Тело"), "у зверя призыва нет модели");
            druid.Vitals.Mana = druid.Vitals.MaxMana;
            druid.Spells.Cooldowns[(int)AbilityKind.Summon] = 0f;
            spells.ServerCast(AbilityKind.Summon);
            Assert.That(druid.GetComponent<PlayerCombat>().Refusal, Does.Contain("стая"), "полная стая — призыв без отказа");

            // Прокачка маны стаю не растит — только прокачка самого заклинания.
            druid.Vitals.Levels[(int)Stat.Mana] = Progression.MaxLevel;
            druid.Vitals.Mana = druid.Vitals.MaxMana;
            druid.Spells.Cooldowns[(int)AbilityKind.Summon] = 0f;
            spells.ServerCast(AbilityKind.Summon);
            yield return null;
            Assert.That(squirrels(), Is.EqualTo(Abilities.SwarmMin), "прокачка маны вырастила стаю");

            // Заклинание прокачано за опыт до предела — стая растёт до пятнадцати.
            druid.Vitals.Experience = 100000;
            for (int i = 0; i < Abilities.MaxSpellLevel; i++) druid.GetComponent<Shop>().Request(DealKind.Upgrade, 10 + (int)AbilityKind.Summon);
            Assert.That(druid.Vitals.SpellLevels[(int)AbilityKind.Summon], Is.EqualTo(Abilities.MaxSpellLevel), "заклинание не прокачалось");
            druid.Vitals.Mana = druid.Vitals.MaxMana;
            druid.Spells.Cooldowns[(int)AbilityKind.Summon] = 0f;
            spells.ServerCast(AbilityKind.Summon);
            yield return null;
            Assert.That(squirrels(), Is.EqualTo(Abilities.SwarmMax), "прокачанное заклинание — не пятнадцать белок");
        }
    }
}
