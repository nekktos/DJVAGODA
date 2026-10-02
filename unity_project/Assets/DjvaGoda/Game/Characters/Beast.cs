// Звери из процедурных частей (решение автора от 02.10: модели — свои,
// кодом): лошадь и волк. Тело, шея, голова, четыре ноги с коленом, хвост,
// у лошади — грива, у волка — уши торчком и пушистый хвост.
//
// Анимация процедурная: ноги ходят диагональными парами (рысь), чем
// быстрее — тем шире шаг; голова покачивается, хвост ходит. Скорость — по
// смещению корня, как у людей (Figure); для упряжки скорость задают снаружи.
using UnityEngine;

namespace DjvaGoda.Game
{
    public class Beast : MonoBehaviour
    {
        readonly Transform[] _hip = new Transform[4];
        readonly Transform[] _knee = new Transform[4];
        Transform _neck, _tail;
        Vector3 _last;
        float _speed, _phase;
        bool _horse;

        /// Наклон шеи вперёд (+x — к морде): лошадь держит голову выше волка.
        const float NeckHorse = 38f;
        const float NeckWolf = 62f;
        /// Высота спины лошади: седло и всадник.
        public const float HorseBack = 1.45f;

        /// Скорость, заданная снаружи (упряжка обоза); отрицательная — считать по смещению.
        public float DrivenSpeed = -1f;

        /// Лошадь ростом 1.6 м в холке, морда вперёд (+z). coat — ключ Palette.
        public static Beast Horse(Transform parent, string coat = "horse", string mane = "mane")
        {
            var root = new GameObject("Лошадь").transform;
            root.SetParent(parent, false);
            var beast = root.gameObject.AddComponent<Beast>();
            beast._horse = true;
            var e = BodyShapes.Ellipsoid();
            var body = BodyShapes.Joint(root, "Корпус", new Vector3(0f, 1.25f, 0f));
            BodyShapes.Part(body, "Туловище", BodyShapes.Loft("конь туловище", new[]
            {
                new BodyShapes.Ring(-0.98f, 0.06f, 0.06f), new BodyShapes.Ring(-0.85f, 0.28f, 0.34f), new BodyShapes.Ring(-0.35f, 0.34f, 0.42f),
                new BodyShapes.Ring(0.35f, 0.33f, 0.42f), new BodyShapes.Ring(0.85f, 0.28f, 0.38f), new BodyShapes.Ring(1.02f, 0.06f, 0.06f),
            }, 12), coat, Vector3.zero, Vector3.one, Quaternion.Euler(90f, 0f, 0f));
            beast._neck = BodyShapes.Joint(body, "Шея", new Vector3(0f, 0.18f, 0.82f));
            beast._neck.localRotation = Quaternion.Euler(NeckHorse, 0f, 0f);
            BodyShapes.Part(beast._neck, "Шея", BodyShapes.Loft("конь шея", new[]
            {
                new BodyShapes.Ring(-0.1f, 0.17f, 0.24f), new BodyShapes.Ring(0.45f, 0.12f, 0.17f), new BodyShapes.Ring(0.62f, 0.11f, 0.13f),
            }), coat, Vector3.zero, Vector3.one);
            BodyShapes.Part(beast._neck, "Грива", BodyShapes.Loft("конь грива", new[]
            {
                new BodyShapes.Ring(-0.05f, 0.04f, 0.06f, -0.17f), new BodyShapes.Ring(0.6f, 0.035f, 0.05f, -0.1f),
            }, 6), mane, Vector3.zero, Vector3.one);
            var head = BodyShapes.Joint(beast._neck, "Голова", new Vector3(0f, 0.62f, 0.05f));
            head.localRotation = Quaternion.Euler(90f, 0f, 0f);
            BodyShapes.Part(head, "Морда", BodyShapes.Loft("конь морда", new[]
            {
                new BodyShapes.Ring(-0.05f, 0.12f, 0.14f), new BodyShapes.Ring(0.3f, 0.09f, 0.1f), new BodyShapes.Ring(0.5f, 0.075f, 0.085f),
                new BodyShapes.Ring(0.54f, 0.03f, 0.03f),
            }), coat, Vector3.zero, Vector3.one);
            for (int s = -1; s <= 1; s += 2)
            {
                BodyShapes.Part(head, "Ухо", BodyShapes.Cone(), coat, new Vector3(0.06f * s, -0.04f, -0.12f), new Vector3(0.05f, 0.14f, 0.05f),
                    Quaternion.Euler(-100f, 0f, 15f * s));
                BodyShapes.Part(head, "Глаз", e, "dark_metal", new Vector3(0.105f * s, 0.06f, -0.05f), new Vector3(0.03f, 0.04f, 0.04f));
            }
            beast._tail = BodyShapes.Joint(body, "Хвост", new Vector3(0f, 0.12f, -0.9f));
            BodyShapes.Part(beast._tail, "Хвост", BodyShapes.Loft("конь хвост", new[]
            {
                new BodyShapes.Ring(0f, 0.06f, 0.06f), new BodyShapes.Ring(-0.35f, 0.09f, 0.07f, -0.08f), new BodyShapes.Ring(-0.75f, 0.03f, 0.03f, -0.12f),
            }, 6), mane, Vector3.zero, Vector3.one);
            beast.Legs(body, coat, new Vector2(0.21f, 0.62f), new Vector2(0.21f, -0.66f), 0.98f, 0.12f, mane);
            return beast;
        }

        /// Волк длиной ~1.2 м, морда вперёд (+z).
        public static Beast Wolf(Transform parent, string fur = "wolf")
        {
            var root = new GameObject("Волк").transform;
            root.SetParent(parent, false);
            var beast = root.gameObject.AddComponent<Beast>();
            var e = BodyShapes.Ellipsoid();
            var body = BodyShapes.Joint(root, "Корпус", new Vector3(0f, 0.6f, 0f));
            BodyShapes.Part(body, "Туловище", BodyShapes.Loft("волк туловище", new[]
            {
                new BodyShapes.Ring(-0.5f, 0.05f, 0.05f), new BodyShapes.Ring(-0.4f, 0.13f, 0.15f), new BodyShapes.Ring(0.05f, 0.15f, 0.19f),
                new BodyShapes.Ring(0.35f, 0.17f, 0.21f), new BodyShapes.Ring(0.52f, 0.06f, 0.06f),
            }, 10), fur, Vector3.zero, Vector3.one, Quaternion.Euler(90f, 0f, 0f));
            beast._neck = BodyShapes.Joint(body, "Шея", new Vector3(0f, 0.08f, 0.45f));
            beast._neck.localRotation = Quaternion.Euler(NeckWolf, 0f, 0f);
            BodyShapes.Part(beast._neck, "Шея", BodyShapes.Loft("волк шея", new[]
            {
                new BodyShapes.Ring(-0.05f, 0.14f, 0.15f), new BodyShapes.Ring(0.2f, 0.1f, 0.11f),
            }), fur, Vector3.zero, Vector3.one);
            var head = BodyShapes.Joint(beast._neck, "Голова", new Vector3(0f, 0.22f, 0.02f));
            head.localRotation = Quaternion.Euler(-50f, 0f, 0f);
            BodyShapes.Part(head, "Череп", e, fur, new Vector3(0f, 0f, 0.02f), new Vector3(0.2f, 0.17f, 0.22f));
            BodyShapes.Part(head, "Морда", BodyShapes.Loft("волк морда", new[]
            {
                new BodyShapes.Ring(0f, 0.065f, 0.06f), new BodyShapes.Ring(0.2f, 0.035f, 0.035f), new BodyShapes.Ring(0.22f, 0.01f, 0.01f),
            }), fur, new Vector3(0f, -0.03f, 0.1f), Vector3.one, Quaternion.Euler(90f, 0f, 0f));
            BodyShapes.Part(head, "Нос", e, "dark_metal", new Vector3(0f, -0.03f, 0.31f), new Vector3(0.04f, 0.035f, 0.035f));
            for (int s = -1; s <= 1; s += 2)
            {
                BodyShapes.Part(head, "Ухо", BodyShapes.Cone(), fur, new Vector3(0.06f * s, 0.07f, -0.02f), new Vector3(0.06f, 0.1f, 0.035f));
                BodyShapes.Part(head, "Глаз", e, "gold", new Vector3(0.055f * s, 0.025f, 0.11f), new Vector3(0.025f, 0.02f, 0.02f));
            }
            beast._tail = BodyShapes.Joint(body, "Хвост", new Vector3(0f, 0.05f, -0.48f));
            beast._tail.localRotation = Quaternion.Euler(-35f, 0f, 0f);
            BodyShapes.Part(beast._tail, "Хвост", BodyShapes.Loft("волк хвост", new[]
            {
                new BodyShapes.Ring(0f, 0.04f, 0.04f), new BodyShapes.Ring(-0.2f, 0.07f, 0.07f, -0.05f), new BodyShapes.Ring(-0.42f, 0.02f, 0.02f, -0.1f),
            }, 6), fur, Vector3.zero, Vector3.one, Quaternion.Euler(180f, 0f, 0f));
            beast.Legs(body, fur, new Vector2(0.09f, 0.3f), new Vector2(0.09f, -0.33f), 0.6f, 0.05f, fur);
            return beast;
        }

        /// Четыре ноги: бедро — колено — голень с копытом/лапой. front/back — (x, z) крепления.
        void Legs(Transform body, string coat, Vector2 front, Vector2 back, float length, float thickness, string hoof)
        {
            float upper = length * 0.5f, lower = length * 0.5f;
            var thigh = BodyShapes.Loft("нога бедро " + length, new[]
            {
                new BodyShapes.Ring(0.08f, thickness * 1.6f, thickness * 1.8f), new BodyShapes.Ring(-upper, thickness * 0.8f, thickness * 0.9f),
            }, 8);
            var shin = BodyShapes.Loft("нога голень " + length, new[]
            {
                new BodyShapes.Ring(0f, thickness * 0.8f, thickness * 0.9f), new BodyShapes.Ring(-lower * 0.85f, thickness * 0.55f, thickness * 0.55f),
                new BodyShapes.Ring(-lower, thickness * 0.8f, thickness * 0.9f),
            }, 8);
            for (int i = 0; i < 4; i++)
            {
                bool isFront = i < 2;
                float s = i % 2 == 0 ? -1f : 1f;
                var at = isFront ? front : back;
                _hip[i] = BodyShapes.Joint(body, "Нога", new Vector3(at.x * s, -0.05f, at.y));
                BodyShapes.Part(_hip[i], "Бедро", thigh, coat, Vector3.zero, Vector3.one);
                _knee[i] = BodyShapes.Joint(_hip[i], "Колено", new Vector3(0f, -upper, 0f));
                BodyShapes.Part(_knee[i], "Голень", shin, coat, Vector3.zero, Vector3.one);
                BodyShapes.Part(_knee[i], "Копыто", BodyShapes.Ellipsoid(), hoof, new Vector3(0f, -lower, 0.02f),
                    new Vector3(thickness * 2f, thickness * 1.2f, thickness * 2.4f));
            }
            // Корпус стоит так, чтобы копыта касались земли: лапы — от -0.05 вниз на length.
            body.localPosition = new Vector3(0f, length + 0.05f, 0f);
        }

        void Start() { _last = transform.position; }

        void LateUpdate()
        {
            float delta = Mathf.Max(Time.deltaTime, 1e-4f);
            var now = transform.position;
            var step = now - _last;
            step.y = 0f;
            _last = now;
            float measured = step.magnitude / delta;
            if (measured > 25f) measured = 0f;
            _speed = Mathf.Lerp(_speed, DrivenSpeed >= 0f ? DrivenSpeed : measured, Mathf.Clamp01(delta * 6f));
            float stride = Mathf.Clamp01(_speed / (_horse ? 8f : 6f));
            _phase += delta * (3f + _speed * 0.9f) * (stride > 0.03f ? 1f : 0f);
            for (int i = 0; i < 4; i++)
            {
                // Рысь: левая передняя с правой задней, правая передняя с левой задней.
                bool diagonal = (i == 0 || i == 3);
                float phase = _phase + (diagonal ? 0f : Mathf.PI);
                float swing = Mathf.Sin(phase) * 30f * stride;
                _hip[i].localRotation = Quaternion.Euler(swing, 0f, 0f);
                float bend = Mathf.Max(0f, Mathf.Cos(phase)) * 45f * stride;
                // Передние гнутся назад, задние — вперёд.
                _knee[i].localRotation = Quaternion.Euler(i < 2 ? bend : -bend, 0f, 0f);
            }
            if (_neck != null)
            {
                var rest = _horse ? NeckHorse : NeckWolf;
                _neck.localRotation = Quaternion.Euler(rest + Mathf.Sin(_phase * 2f) * 5f * stride + Mathf.Sin(Time.time * 0.7f) * 2f, 0f, 0f);
            }
            if (_tail != null)
                _tail.localRotation = Quaternion.Euler(_horse ? 15f : -35f, Mathf.Sin(Time.time * (1.5f + stride * 4f)) * 15f, 0f);
        }
    }
}
