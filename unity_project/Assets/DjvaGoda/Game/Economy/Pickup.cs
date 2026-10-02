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

        public static void Build(Transform root, PickupKind kind)
        {
            var part = GameObject.CreatePrimitive(kind == PickupKind.Loot ? PrimitiveType.Cube : PrimitiveType.Capsule);
            Destroy(part.GetComponent<Collider>());
            part.transform.SetParent(root, false);
            if (kind == PickupKind.Loot)
            {
                part.transform.localPosition = new Vector3(0f, 0.3f, 0f);
                part.transform.localScale = new Vector3(0.9f, 0.6f, 0.7f);
                part.GetComponent<MeshRenderer>().sharedMaterial = Palette.Moving("wood");
            }
            else
            {
                part.transform.localPosition = new Vector3(0f, 0.12f, 0f);
                part.transform.localRotation = Quaternion.Euler(0f, 0f, 90f);
                part.transform.localScale = new Vector3(0.18f, kind == PickupKind.Arm ? 0.35f : 0.45f, 0.18f);
                part.GetComponent<MeshRenderer>().sharedMaterial = Palette.Moving("accent");
            }
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
