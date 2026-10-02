// Снаряд в мире: стрела, болт, огненный шар (перенос combat/projectile.gd).
//
// Полёт считает ядро (ProjectileFlight) — он детерминирован, поэтому снаряд не
// сетевой объект: хост ведёт НАСТОЯЩИЙ снаряд и считает попадания, а клиентам
// рассылает только «выстрел» и «конец» (NetPlayer.ShotRpc / ShotEndRpc), и они
// рисуют тот же полёт у себя. Урон — только у хоста.
using System.Collections.Generic;
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public class Shot : MonoBehaviour
    {
        static int _nextId = 1;
        static readonly Dictionary<int, Shot> Live = new Dictionary<int, Shot>();
        /// Снаряд закончил полёт у хоста: номер и точка — клиентам (шлёт стрелок).
        public System.Action<int, Vector3> Ended;

        public int Id { get; private set; }
        public WeaponKind Kind { get; private set; }
        ProjectileFlight _flight;
        Actor _shooter;
        int _gear;
        bool _authority;

        /// Хост: настоящий снаряд — бьёт.
        public static Shot Fire(WeaponKind kind, V3 origin, V3 dir, Actor shooter, int gear)
        {
            var shot = Make(_nextId++, kind, origin, dir);
            shot._shooter = shooter;
            shot._gear = gear;
            shot._authority = true;
            return shot;
        }

        /// Клиент: тот же полёт, только вид.
        public static void Show(int id, WeaponKind kind, V3 origin, V3 dir)
        {
            if (!Live.ContainsKey(id)) Make(id, kind, origin, dir);
        }

        public static void End(int id, Vector3 at)
        {
            Shot shot;
            if (!Live.TryGetValue(id, out shot) || shot == null) return;
            shot.transform.position = at;
            Destroy(shot.gameObject);
        }

        static Shot Make(int id, WeaponKind kind, V3 origin, V3 dir)
        {
            bool fire = kind == WeaponKind.Spell;
            var go = GameObject.CreatePrimitive(fire ? PrimitiveType.Sphere : PrimitiveType.Cube);
            go.name = Weapons.Names[(int)kind];
            Destroy(go.GetComponent<Collider>());
            go.transform.localScale = fire ? Vector3.one * 0.45f : new Vector3(0.05f, 0.05f, 0.8f);
            go.GetComponent<MeshRenderer>().sharedMaterial = Palette.Moving(fire ? "accent" : "wood");
            go.transform.position = origin.ToUnity();
            var shot = go.AddComponent<Shot>();
            shot.Id = id;
            shot.Kind = kind;
            shot._flight = new ProjectileFlight(kind, origin, dir);
            Live[id] = shot;
            return shot;
        }

        void OnDestroy() { Live.Remove(Id); }

        void Update()
        {
            V3 to;
            var from = _flight.Segment(Time.deltaTime, out to);
            var a = from.ToUnity();
            var b = to.ToUnity();
            if ((b - a).sqrMagnitude > 1e-6f) transform.rotation = Quaternion.LookRotation(b - a);
            if (_authority && Strike(a, b)) return;
            _flight.Advance(to);
            transform.position = b;
            if (_flight.Expired)
            {
                if (_authority) Finish(b);
                else Destroy(gameObject);
            }
        }

        /// Отрезок полёта за кадр: ближайшее — зона чужого или мир.
        bool Strike(Vector3 a, Vector3 b)
        {
            var dir = b - a;
            float length = dir.magnitude;
            if (length < 1e-4f) return false;
            dir /= length;
            float best = float.MaxValue;
            HitZone zone = null;
            Vector3 point = b;
            foreach (var hit in Physics.RaycastAll(a, dir, length, HitZone.Mask, QueryTriggerInteraction.Collide))
            {
                var z = hit.collider.GetComponent<HitZone>();
                if (z == null || z.Owner == null || z.Owner == _shooter || !z.Owner.Alive) continue;
                if (hit.distance < best)
                {
                    best = hit.distance;
                    zone = z;
                    point = hit.point;
                }
            }
            RaycastHit wall;
            if (Physics.Raycast(a, dir, out wall, length, HitZone.WorldMask, QueryTriggerInteraction.Ignore) && wall.distance < best)
            {
                zone = null;
                best = wall.distance;
                point = wall.point;
            }
            if (best == float.MaxValue) return false;
            if (Kind == WeaponKind.Spell) Blast(point);
            else if (zone != null)
            {
                // Пробой строя арбалетом считает сам боец (DamageRules.ToUnit) — здесь без строя.
                float damage = ProjectileFlight.HitDamage(Kind, zone.Zone, _gear, 1f);
                Actor.Strike(zone.Owner, damage, zone.Zone, Kind, false, _shooter);
            }
            Finish(point);
            return true;
        }

        /// Огненный шар: взрыв по всем зонам в радиусе, каждому — раз, по ближайшей зоне.
        void Blast(Vector3 point)
        {
            var zones = new List<ZoneHit>();
            var owners = new Dictionary<int, Actor>();
            foreach (var c in Physics.OverlapSphere(point, Weapons.SpellBlastRadius, HitZone.Mask, QueryTriggerInteraction.Collide))
            {
                var z = c.GetComponent<HitZone>();
                if (z == null || z.Owner == null || !z.Owner.Alive) continue;
                zones.Add(new ZoneHit(z.Owner.Id, z.Zone, c.transform.position.ToCore()));
                owners[z.Owner.Id] = z.Owner;
            }
            foreach (var pair in ProjectileFlight.Blast(point.ToCore(), zones, _gear))
            {
                Actor target;
                if (owners.TryGetValue(pair.Key, out target))
                    Actor.Strike(target, pair.Value.Value, pair.Value.Key.Zone, WeaponKind.Spell, true, _shooter);
            }
        }

        void Finish(Vector3 at)
        {
            if (Ended != null) Ended(Id, at);
            Destroy(gameObject);
        }
    }
}
