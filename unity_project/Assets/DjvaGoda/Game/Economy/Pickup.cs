// Что лежит на земле (перенос economy/loot.gd и combat/severed_limb.gd):
// куча добра с павшего — всё, что было на теле (ответ автора от 29.09), —
// и отрубленная рука или нога. Подбирает тот, кто дошёл и нажал E (Shop): кучу
// — себе в ношу и снаряжение (LootPile ядра), конечность — в трофеи (их тратят
// на некротические протезы у верстака). Лежит 4 минуты.
//
// Считает хост. По сети — префаб Resources/Pickup (PickupNet везёт вид);
// без сети — простой объект.
using System.Collections.Generic;
using DjvaGoda.Core;
using Unity.Netcode;
using UnityEngine;

namespace DjvaGoda.Game
{
    public enum PickupKind { Loot, Arm, Leg }

    public class Pickup : MonoBehaviour
    {
        public static readonly List<Pickup> All = new List<Pickup>();

        public PickupKind Kind;
        /// Куча — что в ней (у хоста).
        public LootPile Pile;
        float _age;

        static GameObject _prefab;

        static bool Networked
        {
            get
            {
                var net = NetworkManager.Singleton;
                return net != null && net.IsListening && net.IsServer;
            }
        }

        static Pickup Make(PickupKind kind, V3 at)
        {
            GameObject go;
            if (Networked)
            {
                if (_prefab == null) _prefab = Resources.Load<GameObject>("Pickup");
                go = Instantiate(_prefab, at.ToUnity(), Quaternion.identity);
            }
            else
            {
                go = new GameObject();
                go.transform.position = at.ToUnity();
            }
            var pickup = go.GetComponent<Pickup>();
            if (pickup == null) pickup = go.AddComponent<Pickup>();
            pickup.Kind = kind;
            go.name = kind == PickupKind.Loot ? "Куча добра" : kind == PickupKind.Arm ? "Отрубленная рука" : "Отрубленная нога";
            if (Networked)
            {
                go.GetComponent<PickupNet>().AssignedKind = kind;
                go.GetComponent<NetworkObject>().Spawn();
            }
            else Build(go.transform, kind);
            return pickup;
        }

        /// Куча с павшего (у хоста): пустую не кладём.
        public static void Drop(V3 at, LootPile pile)
        {
            if (pile.Summary().Length == 0) return;
            Make(PickupKind.Loot, at).Pile = pile;
        }

        public static void DropLimb(V3 at, Limb limb)
        {
            Make(limb == Limb.ArmL || limb == Limb.ArmR ? PickupKind.Arm : PickupKind.Leg, at);
        }

        /// Вид: куча — мешок, ящик и щит; рука или нога — в рукаве или штанине, с кистью или сапогом.
        public static void Build(Transform root, PickupKind kind)
        {
            var e = BodyShapes.Ellipsoid();
            if (kind == PickupKind.Loot)
            {
                BodyShapes.Part(root, "Мешок", e, "linen", new Vector3(0f, 0.3f, 0f), new Vector3(0.7f, 0.6f, 0.6f));
                BodyShapes.Part(root, "Горловина", BodyShapes.Cone(8), "linen", new Vector3(0f, 0.55f, 0f), new Vector3(0.25f, 0.22f, 0.25f));
                BodyShapes.Part(root, "Завязка", e, "leather", new Vector3(0f, 0.58f, 0f), new Vector3(0.18f, 0.05f, 0.18f));
                BodyShapes.Part(root, "Ящик", WeaponShapesBox(), "wood", new Vector3(0.5f, 0.2f, 0.25f), new Vector3(0.45f, 0.4f, 0.45f),
                    Quaternion.Euler(0f, 25f, 0f));
                BodyShapes.Part(root, "Щит", BodyShapes.Loft("щит", new[] { new BodyShapes.Ring(0f, 0.32f, 0.32f), new BodyShapes.Ring(0.04f, 0.3f, 0.3f) }, 12),
                    "wood", new Vector3(-0.45f, 0.04f, 0.2f), Vector3.one, Quaternion.Euler(8f, 0f, 0f));
                return;
            }
            bool arm = kind == PickupKind.Arm;
            float length = arm ? 0.55f : 0.85f;
            var limb = BodyShapes.Loft(arm ? "рука на земле" : "нога на земле", new[]
            {
                new BodyShapes.Ring(0f, arm ? 0.055f : 0.08f, arm ? 0.055f : 0.08f), new BodyShapes.Ring(-length, arm ? 0.038f : 0.05f, arm ? 0.038f : 0.05f),
            }, 8);
            var part = BodyShapes.Part(root, arm ? "Рука" : "Нога", limb, arm ? "linen" : "leather", new Vector3(length * 0.5f, 0.08f, 0f), Vector3.one,
                Quaternion.Euler(0f, 0f, 90f));
            BodyShapes.Part(part, "Срез", e, "accent", Vector3.zero, new Vector3(0.1f, 0.03f, 0.1f));
            if (arm) BodyShapes.Part(part, "Кисть", e, "skin", new Vector3(0f, -length - 0.04f, 0f), new Vector3(0.075f, 0.1f, 0.05f));
            else BodyShapes.Part(part, "Сапог", e, "leather", new Vector3(0f, -length, 0.06f), new Vector3(0.1f, 0.07f, 0.25f));
        }

        static Mesh _box;

        static Mesh WeaponShapesBox()
        {
            if (_box == null)
            {
                var cube = GameObject.CreatePrimitive(PrimitiveType.Cube);
                _box = cube.GetComponent<MeshFilter>().sharedMesh;
                Destroy(cube);
            }
            return _box;
        }

        void OnEnable() { All.Add(this); }
        void OnDisable() { All.Remove(this); }

        void Update()
        {
            if (!MatchNet.Hosting) return;
            _age += Time.deltaTime;
            if (_age >= LootPile.Lifetime) Remove();
        }

        public void Remove()
        {
            var net = GetComponent<NetworkObject>();
            if (net != null && net.IsSpawned) net.Despawn(true);
            else Destroy(gameObject);
        }

        /// Ближайшее в досягаемости подбора.
        public static Pickup Near(V3 point)
        {
            Pickup best = null;
            float bestGap = LootPile.PickupRange;
            foreach (var pickup in All)
            {
                if (pickup == null) continue;
                float gap = pickup.transform.position.ToCore().FlatDistance(point);
                if (gap <= bestGap)
                {
                    bestGap = gap;
                    best = pickup;
                }
            }
            return best;
        }
    }
}
