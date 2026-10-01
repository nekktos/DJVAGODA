// Участник мира: персонаж, боец, постройка, обоз. Реестр всех живых — чтобы
// мозги ядра получали «кого видят» одним списком (Sighting), а не поиском по
// сцене каждый кадр.
//
// Что принадлежит стороне — ищется по стороне (правило 3 Godot-версии:
// поиск по владельцу-персонажу ломался пять раз подряд).
using System.Collections.Generic;
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public abstract class Actor : MonoBehaviour
    {
        static int _nextId = 1;
        public static readonly List<Actor> All = new List<Actor>();

        public int Id { get; private set; }
        public int Side = -1;
        public abstract bool Alive { get; }

        /// Участник пал от удара (у хоста): кто и от чьей руки — для целей партии.
        public static event System.Action<Actor, Actor> Killed;
        /// Постройка — её вид (для досягаемости удара); прочие — null.
        public virtual BuildingKind? Building { get { return null; } }

        public V3 At { get { return transform.position.ToCore(); } }

        protected virtual void OnEnable()
        {
            if (Id == 0) Id = _nextId++;
            All.Add(this);
        }

        protected virtual void OnDisable() { All.Remove(this); }

        /// Удар по участнику. Хост решает, сколько снять (строй, доспех, правило стражи).
        public abstract void TakeDamage(float amount, string zone, WeaponKind? weapon, bool aoe, Actor source);

        /// Удар по цели одним входом: урон и — если бил персонаж — отметка
        /// попадания у него на прицеле (голова, добил ли).
        public static void Strike(Actor target, float amount, string zone, WeaponKind? weapon, bool aoe, Actor source)
        {
            if (target == null) return;
            bool wasAlive = target.Alive;
            target.TakeDamage(amount, zone, weapon, aoe, source);
            if (wasAlive && !target.Alive && Killed != null) Killed(target, source);
            var hitter = source as PlayerCharacter;
            if (hitter != null && hitter != target) hitter.NoteHit(zone == "head", wasAlive && !target.Alive);
        }

        public Sighting Sighting() { return new Sighting(Id, At, Side, Building); }

        /// Живые в радиусе от точки — для мозгов ядра.
        public static List<Sighting> Around(V3 point, float radius, Actor except)
        {
            var result = new List<Sighting>();
            foreach (var actor in All)
            {
                if (actor == except || actor == null || !actor.Alive) continue;
                if (actor.At.FlatDistance(point) > radius) continue;
                result.Add(actor.Sighting());
            }
            return result;
        }

        public static Actor ById(int id)
        {
            foreach (var actor in All)
                if (actor != null && actor.Id == id) return actor;
            return null;
        }
    }
}
