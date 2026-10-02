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
        /// Бег прыжками (белка): задние лапы вместе, корпус подскакивает.
        bool _hop;
        Transform _body;

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

        /// Белка ~0.45 м: вытянутое горизонтальное тельце, голова с мордочкой,
        /// крупными глазами и белыми щеками, уши с кисточками, тонкие лапки
        /// (задние — с бедром), хвост — гладкий изогнутый плюмаж буквой S со
        /// светлым кончиком. Бежит прыжками, задние лапы толкают вместе.
        public static Beast Squirrel(Transform parent)
        {
            var root = new GameObject("Белка").transform;
            root.SetParent(parent, false);
            var beast = root.gameObject.AddComponent<Beast>();
            beast._hop = true;
            var e = BodyShapes.Ellipsoid();
            const string fur = "squirrel", belly = "squirrel_belly", tail = "squirrel_tail";
            var body = BodyShapes.Joint(root, "Корпус", new Vector3(0f, SquirrelHeight, 0f));
            beast._body = body;
            // Тельце вдоль +z: зад шире, к груди сужается, переходит в шею.
            BodyShapes.Part(body, "Туловище", BodyShapes.Loft("белка тело", new[]
            {
                new BodyShapes.Ring(-0.14f, 0.02f, 0.02f), new BodyShapes.Ring(-0.11f, 0.065f, 0.07f), new BodyShapes.Ring(-0.03f, 0.075f, 0.08f),
                new BodyShapes.Ring(0.07f, 0.06f, 0.065f), new BodyShapes.Ring(0.13f, 0.04f, 0.045f),
            }, 10), fur, Vector3.zero, Vector3.one, Quaternion.Euler(90f, 0f, 0f));
            // Белое брюшко снизу.
            BodyShapes.Part(body, "Брюшко", e, belly, new Vector3(0f, -0.045f, 0.0f), new Vector3(0.09f, 0.06f, 0.2f));
            // Голова на шее: мордочка вперёд, щёки, нос, глаза.
            beast._neck = BodyShapes.Joint(body, "Шея", new Vector3(0f, 0.04f, 0.13f));
            beast._neck.localRotation = Quaternion.Euler(-15f, 0f, 0f);
            var head = BodyShapes.Joint(beast._neck, "Голова", new Vector3(0f, 0.04f, 0.04f));
            BodyShapes.Part(head, "Череп", e, fur, Vector3.zero, new Vector3(0.085f, 0.08f, 0.1f));
            BodyShapes.Part(head, "Мордочка", BodyShapes.Loft("белка мордочка", new[]
            {
                new BodyShapes.Ring(0f, 0.03f, 0.028f), new BodyShapes.Ring(0.05f, 0.017f, 0.016f), new BodyShapes.Ring(0.058f, 0.006f, 0.006f),
            }, 8), fur, new Vector3(0f, -0.008f, 0.035f), Vector3.one, Quaternion.Euler(90f, 0f, 0f));
            BodyShapes.Part(head, "Нос", e, "dark_metal", new Vector3(0f, -0.006f, 0.093f), new Vector3(0.014f, 0.011f, 0.01f));
            BodyShapes.Part(head, "Щёки", e, belly, new Vector3(0f, -0.022f, 0.035f), new Vector3(0.06f, 0.035f, 0.05f));
            for (int s = -1; s <= 1; s += 2)
            {
                BodyShapes.Part(head, "Глаз", e, "dark_metal", new Vector3(0.033f * s, 0.012f, 0.027f), new Vector3(0.018f, 0.022f, 0.02f));
                BodyShapes.Part(head, "Блик", e, "linen", new Vector3(0.038f * s, 0.018f, 0.033f), new Vector3(0.005f, 0.005f, 0.005f));
                var ear = BodyShapes.Joint(head, "Ухо", new Vector3(0.026f * s, 0.035f, -0.015f));
                ear.localRotation = Quaternion.Euler(-10f, 0f, -12f * s);
                BodyShapes.Part(ear, "Ухо", BodyShapes.Cone(6), fur, Vector3.zero, new Vector3(0.026f, 0.045f, 0.014f));
                BodyShapes.Part(ear, "Кисточка", BodyShapes.Cone(5), "mane", new Vector3(0f, 0.038f, 0f), new Vector3(0.01f, 0.03f, 0.008f));
            }
            // Хвост: гладкий плюмаж из одного тела вращения, изогнутый S — вверх
            // от крупа, назад и завитком вперёд над спиной; к кончику светлеет.
            beast._tail = BodyShapes.Joint(body, "Хвост", new Vector3(0f, 0.02f, -0.12f));
            BodyShapes.Part(beast._tail, "Хвост", BodyShapes.Loft("белка хвост", new[]
            {
                new BodyShapes.Ring(0f, 0.03f, 0.03f, 0f), new BodyShapes.Ring(0.05f, 0.065f, 0.06f, -0.06f),
                new BodyShapes.Ring(0.12f, 0.085f, 0.075f, -0.09f), new BodyShapes.Ring(0.2f, 0.09f, 0.08f, -0.06f),
                new BodyShapes.Ring(0.26f, 0.08f, 0.07f, 0.0f), new BodyShapes.Ring(0.3f, 0.06f, 0.055f, 0.07f),
                new BodyShapes.Ring(0.315f, 0.03f, 0.03f, 0.12f),
            }, 10), tail, Vector3.zero, Vector3.one);
            BodyShapes.Part(beast._tail, "Кончик хвоста", e, belly, new Vector3(0f, 0.31f, 0.12f), new Vector3(0.05f, 0.035f, 0.05f));
            // Лапки: передние тонкие, задние — бедро и длинная ступня.
            var foreleg = BodyShapes.Loft("белка передняя лапа", new[] { new BodyShapes.Ring(0f, 0.017f, 0.019f), new BodyShapes.Ring(-0.13f, 0.011f, 0.012f) }, 6);
            var thigh = BodyShapes.Loft("белка бедро", new[] { new BodyShapes.Ring(0.02f, 0.035f, 0.045f), new BodyShapes.Ring(-0.06f, 0.02f, 0.022f) }, 6);
            var shin = BodyShapes.Loft("белка голень", new[] { new BodyShapes.Ring(0f, 0.016f, 0.018f), new BodyShapes.Ring(-0.1f, 0.012f, 0.012f) }, 6);
            for (int i = 0; i < 4; i++)
            {
                bool front = i < 2;
                float s = i % 2 == 0 ? -1f : 1f;
                beast._hip[i] = BodyShapes.Joint(body, "Лапа", new Vector3(0.04f * s, front ? -0.03f : -0.02f, front ? 0.09f : -0.08f));
                if (front)
                {
                    BodyShapes.Part(beast._hip[i], "Лапа", foreleg, fur, Vector3.zero, Vector3.one);
                    beast._knee[i] = BodyShapes.Joint(beast._hip[i], "Кисть", new Vector3(0f, -0.13f, 0f));
                    BodyShapes.Part(beast._knee[i], "Кисть", e, "squirrel_tail", new Vector3(0f, -0.005f, 0.01f), new Vector3(0.022f, 0.012f, 0.03f));
                }
                else
                {
                    BodyShapes.Part(beast._hip[i], "Бедро", thigh, fur, Vector3.zero, Vector3.one);
                    beast._knee[i] = BodyShapes.Joint(beast._hip[i], "Скакательный", new Vector3(0f, -0.06f, 0f));
                    beast._knee[i].localRotation = Quaternion.Euler(-35f, 0f, 0f);
                    BodyShapes.Part(beast._knee[i], "Голень", shin, fur, Vector3.zero, Vector3.one);
                    BodyShapes.Part(beast._knee[i], "Ступня", e, "squirrel_tail", new Vector3(0f, -0.1f, 0.03f), new Vector3(0.024f, 0.012f, 0.065f));
                }
            }
            return beast;
        }

        /// Высота корпуса белки над землёй (лапки до земли).
        const float SquirrelHeight = 0.17f;

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

        /// Прыжок белки: корпус взлетает дугой, задние лапы толкают вместе,
        /// передние тянутся вперёд; стоя — хвост подёргивается, голова озирается.
        void Hop(float stride)
        {
            float jump = Mathf.Max(0f, Mathf.Sin(_phase * 1.6f));
            _body.localPosition = new Vector3(0f, SquirrelHeight + jump * 0.1f * stride, 0f);
            _body.localRotation = Quaternion.Euler(-Mathf.Cos(_phase * 1.6f) * 12f * stride, 0f, 0f);
            for (int i = 0; i < 4; i++)
            {
                bool front = i < 2;
                float swing = Mathf.Sin(_phase * 1.6f + (front ? 0f : Mathf.PI)) * 45f * stride;
                _hip[i].localRotation = Quaternion.Euler(front ? -swing : swing, 0f, 0f);
            }
            _neck.localRotation = Quaternion.Euler(0f, Mathf.Sin(Time.time * 2.3f) * 25f * (1f - stride), 0f);
            // Хвост на бегу вытягивается назад, стоя — поднят и подрагивает.
            _tail.localRotation = Quaternion.Euler(-35f * stride + Mathf.Sin(Time.time * 7f) * 5f, 0f, 0f);
        }

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
            if (_hop)
            {
                Hop(stride);
                return;
            }
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
