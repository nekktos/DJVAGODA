// Лошадь (перенос units/horse.gd). Не боец: не дерётся, не входит в отряд и
// не принадлежит стороне. Её уводят из упряжки стоящего чужого обоза и ездят
// сами (E рядом — сесть, E верхом — спешиться); её можно убить. Пока на ней
// едут, её тело убрано, а всадник быстрее (HorseStats.RideSpeedScale в ядре).
//
// В общий реестр участников (Actor.All) лошадь НЕ входит: у неё нет стороны,
// и мозги бойцов, обозы и ИИ видели бы в ней врага. Удар по ней идёт тем же
// входом (Actor.Strike), реестр у неё свой — Horses.
//
// Считает хост. По сети — префаб Resources/Horse (NetworkTransform хоста,
// HorseNet — под седлом ли); без сети — простой объект.
using System.Collections.Generic;
using DjvaGoda.Core;
using Unity.Netcode;
using UnityEngine;

namespace DjvaGoda.Game
{
    public class HorseActor : Actor
    {
        public static readonly List<HorseActor> Horses = new List<HorseActor>();

        public float Health = HorseStats.Health;
        /// Всадник (у хоста); null — стоит свободная.
        public PlayerCharacter Rider;
        /// Под седлом — для подсказок у клиентов (HorseNet) и у хоста.
        public bool Ridden;
        Transform _view;

        public override bool Alive { get { return Health > 0f; } }

        static GameObject _prefab;

        static bool Networked
        {
            get
            {
                var net = NetworkManager.Singleton;
                return net != null && net.IsListening && net.IsServer;
            }
        }

        protected override void OnEnable() { Horses.Add(this); }
        protected override void OnDisable() { Horses.Remove(this); }

        /// Лошадь на земле (у хоста).
        public static HorseActor Spawn(V3 at)
        {
            var world = Object.FindAnyObjectByType<World>();
            if (world != null && world.Relief != null) at = new V3(at.X, world.Relief.Height(at.X, at.Z), at.Z);
            GameObject go;
            if (Networked)
            {
                if (_prefab == null) _prefab = Resources.Load<GameObject>("Horse");
                go = Instantiate(_prefab, at.ToUnity(), Quaternion.identity);
            }
            else
            {
                go = new GameObject();
                go.transform.position = at.ToUnity();
            }
            go.name = "Лошадь";
            var horse = go.GetComponent<HorseActor>();
            if (horse == null) horse = go.AddComponent<HorseActor>();
            if (Networked) go.GetComponent<NetworkObject>().Spawn();
            else horse.Build(true);
            return horse;
        }

        /// Вид (коробки-заглушки до ассетов) и зона попадания — у хоста.
        public void Build(bool hittable)
        {
            if (_view != null) return;
            _view = new GameObject("Вид").transform;
            _view.SetParent(transform, false);
            Box("Тело", new Vector3(0f, 1.3f, 0f), new Vector3(0.8f, 0.9f, 2.2f));
            Box("Шея", new Vector3(0f, 1.9f, 1.0f), new Vector3(0.4f, 0.9f, 0.5f));
            Box("Голова", new Vector3(0f, 2.3f, 1.35f), new Vector3(0.35f, 0.35f, 0.7f));
            for (int i = 0; i < 4; i++)
                Box("Нога", new Vector3(i % 2 == 0 ? -0.3f : 0.3f, 0.45f, i < 2 ? 0.8f : -0.8f), new Vector3(0.2f, 0.9f, 0.2f));
            if (!hittable) return;
            var zone = new GameObject("Зона попадания");
            zone.layer = HitZone.Layer;
            zone.transform.SetParent(transform, false);
            zone.transform.localPosition = new Vector3(0f, 1.3f, 0f);
            var box = zone.AddComponent<BoxCollider>();
            box.isTrigger = true;
            box.size = new Vector3(1.4f, 2f, 3f);
            var hit = zone.AddComponent<HitZone>();
            hit.Zone = "horse";
            hit.Owner = this;
        }

        void Box(string name, Vector3 at, Vector3 size)
        {
            var part = GameObject.CreatePrimitive(PrimitiveType.Cube);
            part.name = name;
            Destroy(part.GetComponent<Collider>());
            part.transform.SetParent(_view, false);
            part.transform.localPosition = at;
            part.transform.localScale = size;
            part.GetComponent<MeshRenderer>().sharedMaterial = Palette.Of("bark");
        }

        /// Под седлом — тела нет; спешились — снова видна.
        public void Show(bool ridden)
        {
            Ridden = ridden;
            if (_view != null) _view.gameObject.SetActive(!ridden);
            foreach (var zone in GetComponentsInChildren<Collider>(true)) zone.enabled = !ridden;
        }

        public bool Free { get { return Alive && Rider == null && !Ridden; } }

        /// Сесть (у хоста).
        public bool Mount(PlayerCharacter rider)
        {
            if (!Free) return false;
            Rider = rider;
            Show(true);
            return true;
        }

        /// Спешиться рядом со всадником (у хоста): лошадь не остаётся на другом конце карты.
        public void Dismount(V3 at)
        {
            Rider = null;
            var world = Object.FindAnyObjectByType<World>();
            if (world != null && world.Relief != null) at = new V3(at.X, world.Relief.Height(at.X, at.Z), at.Z);
            transform.position = at.ToUnity();
            Show(false);
        }

        void Update()
        {
            // Под всадником лошадь едет с ним: спешиться можно где угодно.
            if (Rider != null && MatchNet.Hosting) transform.position = Rider.transform.position;
        }

        public override void TakeDamage(float amount, string zone, WeaponKind? weapon, bool aoe, Actor source)
        {
            if (!Alive || Ridden) return;
            Health = Mathf.Max(0f, Health - amount);
            if (Alive) return;
            Debug.Log("[лошадь] убита");
            var net = GetComponent<NetworkObject>();
            if (net != null && net.IsSpawned) net.Despawn(true);
            else Destroy(gameObject);
        }

        /// Свободная лошадь в досягаемости.
        public static HorseActor Near(V3 point)
        {
            HorseActor best = null;
            float bestGap = HorseStats.MountRange;
            foreach (var horse in Horses)
            {
                if (horse == null || !horse.Alive || horse.Ridden) continue;
                float gap = horse.At.FlatDistance(point);
                if (gap <= bestGap)
                {
                    bestGap = gap;
                    best = horse;
                }
            }
            return best;
        }
    }
}
