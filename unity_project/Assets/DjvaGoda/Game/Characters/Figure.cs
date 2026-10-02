// Человек из процедурных частей (решение автора от 02.10: модели — свои,
// кодом). Рост 1.8 м, части стоят там же, где зоны попадания HitZone.Humanoid:
// голова 1.62, торс 0.8–1.44, руки по бокам, ноги от бёдер на 0.9.
//
// Скелет — суставы-узлы: таз, торс, шея, голова, плечи, локти, бёдра,
// колени. Анимация процедурная, без клипов: шаг по скорости корня (ноги
// и руки в противофазе, колени гнутся на возврате), взмах правой при ударе,
// вскинутые руки с луком, дыхание. Отрубленная рука или нога исчезает, на
// её месте — протез его ступени (деревяшка, кованый, мастерский, костяной).
//
// Вид (FigureLook) — одежда, доспех, шлем или капюшон, плащ, уши: стороны
// и роли различимы издали и без цвета — по силуэту.
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public enum Headgear { None, Hair, Hood, Helmet, HornedHelmet, StrawHat, Circlet }

    public struct FigureLook
    {
        public string Skin;
        public string Hair;
        /// Рубаха и штаны.
        public string Tunic;
        public string Legs;
        public string Boots;
        /// Нагрудник поверх рубахи; null — без доспеха.
        public string Armor;
        public string Pauldrons;
        public string Cape;
        public string Belt;
        public Headgear Head;
        public string HeadMaterial;
        public bool PointedEars;
        /// Ширина плеч и торса: эльф стройнее, распорядитель шире.
        public float Build;
        public float Height;

        public static FigureLook Hero(Faction side)
        {
            string cloth = "side_" + (int)side;
            switch (side)
            {
                case Faction.Villain:
                    return new FigureLook
                    {
                        Skin = "pale_skin", Hair = "hair", Tunic = cloth, Legs = "dark_metal", Boots = "leather",
                        Armor = "dark_metal", Pauldrons = "dark_metal", Cape = cloth, Belt = "leather",
                        Head = Headgear.HornedHelmet, HeadMaterial = "dark_metal", Build = 1.08f, Height = 1.02f,
                    };
                case Faction.Elves:
                    return new FigureLook
                    {
                        Skin = "skin", Hair = "fair_hair", Tunic = cloth, Legs = "leather", Boots = "leather",
                        Belt = "leather", Cape = cloth, Head = Headgear.Hood, HeadMaterial = cloth, PointedEars = true,
                        Build = 0.9f, Height = 1.02f,
                    };
                default:
                    return new FigureLook
                    {
                        Skin = "skin", Hair = "hair", Tunic = cloth, Legs = cloth, Boots = "leather",
                        Armor = "metal", Pauldrons = "metal", Belt = "leather", Head = Headgear.Helmet, HeadMaterial = "metal",
                        Build = 1f, Height = 1f,
                    };
            }
        }

        public static FigureLook Agent(AgentRole role, Faction side)
        {
            string cloth = "side_" + (int)side;
            var look = Hero(side);
            switch (role)
            {
                case AgentRole.Labourer:
                    return new FigureLook
                    {
                        Skin = "skin", Hair = "hair", Tunic = "linen", Legs = "leather", Boots = "leather", Belt = cloth,
                        Head = Headgear.StrawHat, HeadMaterial = "thatch", Build = 0.95f, Height = 0.96f,
                    };
                case AgentRole.Archer:
                    look.Armor = null;
                    look.Pauldrons = null;
                    look.Cape = null;
                    look.Head = Headgear.Hood;
                    look.HeadMaterial = side == Faction.Elves ? cloth : "leather";
                    look.Legs = "leather";
                    look.Height = 0.98f;
                    return look;
                case AgentRole.Champion:
                    look.Pauldrons = "gold";
                    look.Cape = cloth;
                    look.Build = 1.18f;
                    look.Height = 1.08f;
                    if (side == Faction.Elves)
                    {
                        // Старейшина: без капюшона, с обручем, в длинной рубахе.
                        look.Head = Headgear.Circlet;
                        look.HeadMaterial = "gold";
                        look.Hair = "pale_skin";
                    }
                    return look;
                default:
                    // Мечник: рубаха стороны, шлем; злодею — без рогов (рога у вожака).
                    look.Cape = null;
                    look.Pauldrons = null;
                    look.Height = 0.98f;
                    if (look.Head == Headgear.HornedHelmet || look.Head == Headgear.Hood)
                    {
                        look.Head = Headgear.Helmet;
                        look.HeadMaterial = side == Faction.Villain ? "dark_metal" : "metal";
                    }
                    if (side == Faction.Elves) look.Armor = "leather";
                    return look;
            }
        }
    }

    public class Figure : MonoBehaviour
    {
        public const float HipHeight = 0.92f;
        public const float ShoulderHeight = 1.42f;

        Transform _hips, _torso, _head;
        readonly Transform[] _shoulder = new Transform[2];
        readonly Transform[] _elbow = new Transform[2];
        readonly Transform[] _hip = new Transform[2];
        readonly Transform[] _knee = new Transform[2];
        /// Целые конечности по Limb (0 рука л., 1 рука пр., 2 нога л., 3 нога пр.) и протезы на их месте.
        readonly Transform[] _limb = new Transform[4];
        readonly Transform[] _prosthesis = new Transform[4];
        readonly int[] _shownTier = { -1, -1, -1, -1 };
        int _shownSevered = -1;

        public Transform HandR { get; private set; }
        public Transform HandL { get; private set; }

        Vector3 _last;
        float _speed;
        float _phase;
        float _swing = -1f;
        float _lastCooldown;
        PlayerCharacter _character;
        PlayerCombat _combat;

        /// Построить фигуру под корнем как «Тело» (ноги в начале координат корня).
        public static Figure Build(Transform root, FigureLook look)
        {
            var body = new GameObject("Тело").transform;
            body.SetParent(root, false);
            body.localScale = Vector3.one * (look.Height <= 0f ? 1f : look.Height);
            var figure = body.gameObject.AddComponent<Figure>();
            figure.Assemble(look);
            return figure;
        }

        void Assemble(FigureLook look)
        {
            float w = look.Build <= 0f ? 1f : look.Build;
            var e = BodyShapes.Ellipsoid();
            _hips = BodyShapes.Joint(transform, "Таз", new Vector3(0f, HipHeight, 0f));

            // Торс: от пояса до плеч, сечение — эллипс, грудь чуть вперёд.
            _torso = BodyShapes.Joint(_hips, "Торс", Vector3.zero);
            var torso = BodyShapes.Loft("торс", new[]
            {
                new BodyShapes.Ring(-0.12f, 0.17f, 0.11f), new BodyShapes.Ring(0.05f, 0.16f, 0.10f),
                new BodyShapes.Ring(0.25f, 0.19f, 0.12f, 0.01f), new BodyShapes.Ring(0.44f, 0.22f, 0.12f, 0.01f),
                new BodyShapes.Ring(0.52f, 0.14f, 0.09f), new BodyShapes.Ring(0.55f, 0.06f, 0.05f),
            });
            BodyShapes.Part(_torso, "Рубаха", torso, look.Tunic, Vector3.zero, new Vector3(w, 1f, w));
            // Подол рубахи — до середины бедра; у старейшины и распорядителя — длиннее.
            var hem = BodyShapes.Loft("подол", new[]
            {
                new BodyShapes.Ring(0f, 0.18f, 0.12f), new BodyShapes.Ring(-0.22f, 0.22f, 0.15f), new BodyShapes.Ring(-0.24f, 0.0001f, 0.0001f),
            });
            BodyShapes.Part(_torso, "Подол", hem, look.Tunic, new Vector3(0f, -0.08f, 0f), new Vector3(w, 1f, w));
            if (look.Armor != null)
            {
                var plate = BodyShapes.Loft("нагрудник", new[]
                {
                    new BodyShapes.Ring(0.02f, 0.175f, 0.115f), new BodyShapes.Ring(0.25f, 0.205f, 0.135f, 0.015f),
                    new BodyShapes.Ring(0.45f, 0.225f, 0.13f, 0.01f), new BodyShapes.Ring(0.5f, 0.16f, 0.1f),
                });
                BodyShapes.Part(_torso, "Нагрудник", plate, look.Armor, Vector3.zero, new Vector3(w, 1f, w));
            }
            if (look.Belt != null)
            {
                var belt = BodyShapes.Loft("пояс", new[] { new BodyShapes.Ring(-0.03f, 0.175f, 0.115f), new BodyShapes.Ring(0.03f, 0.175f, 0.115f) });
                BodyShapes.Part(_torso, "Пояс", belt, look.Belt, Vector3.zero, new Vector3(w, 1f, w));
            }
            if (look.Cape != null)
                BodyShapes.Part(_torso, "Плащ", BodyShapes.Cape(), look.Cape, new Vector3(0f, 0.48f, -0.12f), new Vector3(0.46f * w, 1.2f, 1f));

            // Шея и голова.
            BodyShapes.Part(_torso, "Шея", BodyShapes.Loft("шея", new[] { new BodyShapes.Ring(0f, 0.055f, 0.055f), new BodyShapes.Ring(0.1f, 0.05f, 0.05f) }),
                look.Skin, new Vector3(0f, 0.52f, 0f), Vector3.one);
            _head = BodyShapes.Joint(_torso, "Голова", new Vector3(0f, 0.71f, 0f));
            BodyShapes.Part(_head, "Лицо", e, look.Skin, Vector3.zero, new Vector3(0.2f, 0.25f, 0.22f));
            BodyShapes.Part(_head, "Нос", e, look.Skin, new Vector3(0f, -0.01f, 0.11f), new Vector3(0.04f, 0.06f, 0.05f));
            for (int s = -1; s <= 1; s += 2)
            {
                BodyShapes.Part(_head, "Глаз", e, "dark_metal", new Vector3(0.045f * s, 0.03f, 0.098f), new Vector3(0.03f, 0.022f, 0.02f));
                if (look.PointedEars)
                    BodyShapes.Part(_head, "Ухо", BodyShapes.Cone(), look.Skin, new Vector3(0.1f * s, 0.02f, -0.01f), new Vector3(0.04f, 0.13f, 0.025f),
                        Quaternion.Euler(0f, 0f, -70f * s));
            }
            HeadGear(look);

            // Руки: плечо — локоть — кисть; наплечник поверх.
            var upper = BodyShapes.Loft("плечо", new[] { new BodyShapes.Ring(0.03f, 0.06f, 0.06f), new BodyShapes.Ring(-0.29f, 0.047f, 0.047f) });
            var fore = BodyShapes.Loft("предплечье", new[] { new BodyShapes.Ring(0f, 0.046f, 0.046f), new BodyShapes.Ring(-0.25f, 0.036f, 0.034f) });
            for (int i = 0; i < 2; i++)
            {
                float s = i == 0 ? -1f : 1f;
                _shoulder[i] = BodyShapes.Joint(_torso, i == 0 ? "Плечо л." : "Плечо пр.", new Vector3(0.25f * w * s, ShoulderHeight - HipHeight, 0f));
                _shoulder[i].localRotation = Quaternion.Euler(0f, 0f, 7f * s);
                _limb[i] = _shoulder[i];
                BodyShapes.Part(_shoulder[i], "Рукав", upper, look.Tunic, Vector3.zero, Vector3.one);
                if (look.Pauldrons != null)
                    BodyShapes.Part(_shoulder[i], "Наплечник", BodyShapes.Dome(), look.Pauldrons, new Vector3(0.01f * s, 0.01f, 0f), new Vector3(0.17f, 0.13f, 0.17f));
                _elbow[i] = BodyShapes.Joint(_shoulder[i], "Локоть", new Vector3(0f, -0.29f, 0f));
                BodyShapes.Part(_elbow[i], "Предплечье", fore, look.Armor ?? look.Skin, Vector3.zero, Vector3.one);
                BodyShapes.Part(_elbow[i], "Наруч", BodyShapes.Loft("наруч", new[] { new BodyShapes.Ring(-0.1f, 0.048f, 0.046f), new BodyShapes.Ring(-0.24f, 0.042f, 0.04f) }),
                    "leather", Vector3.zero, Vector3.one);
                BodyShapes.Part(_elbow[i], "Кисть", e, look.Skin, new Vector3(0f, -0.3f, 0.01f), new Vector3(0.075f, 0.1f, 0.05f));
                // Хват — узел без масштаба: оружие в сплюснутой кисти сплющилось бы.
                var grip = BodyShapes.Joint(_elbow[i], "Хват", new Vector3(0f, -0.3f, 0.01f));
                if (i == 0) HandL = grip; else HandR = grip;
            }

            // Ноги: бедро — колено — голень — стопа; сапог поверх голени.
            var thigh = BodyShapes.Loft("бедро", new[] { new BodyShapes.Ring(0.04f, 0.085f, 0.085f), new BodyShapes.Ring(-0.44f, 0.058f, 0.058f) });
            var shin = BodyShapes.Loft("голень", new[] { new BodyShapes.Ring(0f, 0.058f, 0.058f), new BodyShapes.Ring(-0.2f, 0.054f, 0.056f, 0.008f), new BodyShapes.Ring(-0.42f, 0.04f, 0.04f) });
            var boot = BodyShapes.Loft("сапог", new[] { new BodyShapes.Ring(-0.18f, 0.06f, 0.062f), new BodyShapes.Ring(-0.43f, 0.05f, 0.05f) });
            for (int i = 0; i < 2; i++)
            {
                float s = i == 0 ? -1f : 1f;
                _hip[i] = BodyShapes.Joint(_hips, i == 0 ? "Бедро л." : "Бедро пр.", new Vector3(0.1f * w * s, 0f, 0f));
                _limb[2 + i] = _hip[i];
                BodyShapes.Part(_hip[i], "Штанина", thigh, look.Legs, Vector3.zero, Vector3.one);
                _knee[i] = BodyShapes.Joint(_hip[i], "Колено", new Vector3(0f, -0.44f, 0f));
                BodyShapes.Part(_knee[i], "Голень", shin, look.Legs, Vector3.zero, Vector3.one);
                if (look.Boots != null) BodyShapes.Part(_knee[i], "Сапог", boot, look.Boots, Vector3.zero, Vector3.one);
                BodyShapes.Part(_knee[i], "Стопа", e, look.Boots ?? look.Skin, new Vector3(0f, -0.44f, 0.06f), new Vector3(0.1f, 0.07f, 0.25f));
            }
        }

        void HeadGear(FigureLook look)
        {
            var dome = BodyShapes.Dome();
            string gear = look.HeadMaterial ?? look.Tunic;
            switch (look.Head)
            {
                case Headgear.Helmet:
                case Headgear.HornedHelmet:
                    BodyShapes.Part(_head, "Шлем", dome, gear, new Vector3(0f, 0.02f, -0.005f), new Vector3(0.25f, 0.26f, 0.26f));
                    BodyShapes.Part(_head, "Обод", BodyShapes.Loft("обод", new[] { new BodyShapes.Ring(0f, 0.13f, 0.135f), new BodyShapes.Ring(0.03f, 0.13f, 0.135f) }),
                        gear, new Vector3(0f, 0.01f, -0.005f), Vector3.one);
                    BodyShapes.Part(_head, "Наносник", BodyShapes.Ellipsoid(), gear, new Vector3(0f, 0.0f, 0.12f), new Vector3(0.025f, 0.09f, 0.02f));
                    if (look.Head == Headgear.HornedHelmet)
                        for (int s = -1; s <= 1; s += 2)
                            BodyShapes.Part(_head, "Рог", BodyShapes.Cone(), "linen", new Vector3(0.11f * s, 0.08f, 0f), new Vector3(0.06f, 0.2f, 0.06f),
                                Quaternion.Euler(0f, 0f, -55f * s));
                    break;
                case Headgear.Hood:
                    // Купол сдвинут назад: спереди лицо открыто (лицо выступает до z = 0.11).
                    BodyShapes.Part(_head, "Капюшон", dome, gear, new Vector3(0f, 0.02f, -0.05f), new Vector3(0.26f, 0.31f, 0.27f));
                    BodyShapes.Part(_head, "Капюшон сзади", BodyShapes.Loft("капюшон", new[]
                    {
                        new BodyShapes.Ring(0.02f, 0.135f, 0.12f, -0.03f), new BodyShapes.Ring(-0.16f, 0.15f, 0.12f, -0.04f), new BodyShapes.Ring(-0.2f, 0.18f, 0.13f, -0.02f),
                    }), gear, Vector3.zero, Vector3.one);
                    break;
                case Headgear.StrawHat:
                    BodyShapes.Part(_head, "Поля", BodyShapes.Cone(), gear, new Vector3(0f, 0.06f, 0f), new Vector3(0.48f, 0.08f, 0.48f));
                    BodyShapes.Part(_head, "Тулья", BodyShapes.Cone(), gear, new Vector3(0f, 0.08f, 0f), new Vector3(0.22f, 0.16f, 0.22f));
                    break;
                case Headgear.Circlet:
                    BodyShapes.Part(_head, "Волосы", dome, look.Hair ?? "hair", new Vector3(0f, 0.02f, -0.01f), new Vector3(0.215f, 0.22f, 0.23f));
                    BodyShapes.Part(_head, "Обруч", BodyShapes.Loft("обруч", new[] { new BodyShapes.Ring(0f, 0.11f, 0.12f), new BodyShapes.Ring(0.02f, 0.11f, 0.12f) }),
                        gear, new Vector3(0f, 0.05f, 0f), Vector3.one);
                    break;
                default:
                    BodyShapes.Part(_head, "Волосы", dome, look.Hair ?? "hair", new Vector3(0f, 0.02f, -0.01f), new Vector3(0.215f, 0.22f, 0.23f));
                    break;
            }
        }

        void Start()
        {
            _character = GetComponentInParent<PlayerCharacter>();
            _combat = GetComponentInParent<PlayerCombat>();
            _last = transform.position;
        }

        /// Удар: правая рука взмывает и рубит (бойцы и персонажи у хоста и владельца).
        public void Swing()
        {
            _swing = 0f;
            Sfx.Play(SoundKind.Swing, transform.position + Vector3.up * 1.4f, 0.6f);
        }

        void LateUpdate()
        {
            if (_hips == null)
            {
                // Фигура без скелета (копия, собранная не через Build) — не крутить её.
                Debug.LogError("[фигура] без скелета: " + Path(transform));
                enabled = false;
                return;
            }
            float delta = Mathf.Max(Time.deltaTime, 1e-4f);
            var now = transform.position;
            var step = now - _last;
            step.y = 0f;
            _last = now;
            _speed = Mathf.Lerp(_speed, step.magnitude / delta, Mathf.Clamp01(delta * 8f));
            if (_speed > 15f) _speed = 0f; // скачок телепорта — не бег

            if (_combat != null)
            {
                if (_combat.Cooldown > _lastCooldown + 0.05f && !IsRanged(_combat.Weapon)) Swing();
                _lastCooldown = _combat.Cooldown;
            }

            float stride = Mathf.Clamp01(_speed / 6f);
            float before = _phase;
            _phase += delta * (2.2f + _speed * 1.1f) * (stride > 0.05f ? 1f : 0f);
            // Шаг — когда нога проходит вертикаль (каждые пол-оборота фазы); в седле не топаем.
            if (stride > 0.2f && Mathf.Floor(_phase / Mathf.PI) != Mathf.Floor(before / Mathf.PI) && !Riding)
                Sfx.Footfall(false, transform.position);
            float leg = Mathf.Sin(_phase) * 38f * stride;
            for (int i = 0; i < 2; i++)
            {
                float s = i == 0 ? 1f : -1f;
                _hip[i].localRotation = Quaternion.Euler(leg * s, 0f, 0f);
                float bend = Mathf.Max(0f, -Mathf.Sin(_phase) * s) * 55f * stride;
                _knee[i].localRotation = Quaternion.Euler(bend, 0f, 0f);
                float side = i == 0 ? -1f : 1f;
                _shoulder[i].localRotation = Quaternion.Euler(-leg * s * 0.7f, 0f, 7f * side);
                _elbow[i].localRotation = Quaternion.Euler(-12f - stride * 20f, 0f, 0f);
            }
            // Дыхание и наклон корпуса на бегу.
            _torso.localRotation = Quaternion.Euler(stride * 6f, 0f, 0f);
            _hips.localPosition = new Vector3(0f, HipHeight + Mathf.Abs(Mathf.Sin(_phase)) * 0.04f * stride, 0f);
            _head.localRotation = Quaternion.Euler(Mathf.Sin(Time.time * 1.7f) * 1.5f, 0f, 0f);

            // Лук и арбалет — руки вперёд, как при прицеливании.
            if (_combat != null && IsRanged(_combat.Weapon) && _character != null && _character.Alive)
            {
                _shoulder[1].localRotation = Quaternion.Euler(-80f, 0f, 0f);
                _elbow[1].localRotation = Quaternion.Euler(-10f, 0f, 0f);
                _shoulder[0].localRotation = Quaternion.Euler(-85f, 0f, 15f);
                _elbow[0].localRotation = Quaternion.Euler(-40f, 0f, 0f);
            }
            // Удар правой: замах вверх и рубящий ход вниз за 0.35 с.
            if (_swing >= 0f)
            {
                _swing += delta / 0.35f;
                float t = Mathf.Clamp01(_swing);
                float raise = t < 0.35f ? Mathf.Lerp(0f, -150f, t / 0.35f) : Mathf.Lerp(-150f, -20f, (t - 0.35f) / 0.65f);
                _shoulder[1].localRotation = Quaternion.Euler(raise, 0f, 10f);
                _elbow[1].localRotation = Quaternion.Euler(-25f, 0f, 0f);
                _torso.localRotation = Quaternion.Euler(stride * 6f, Mathf.Lerp(-20f, 25f, t), 0f);
                if (_swing >= 1f) _swing = -1f;
            }
            Ride();
            Wounds();
        }

        Beast _mount;
        bool Riding { get { return _mount != null && _mount.gameObject.activeSelf; } }

        /// Верхом: конь под седлом, ноги по бокам, руки на поводьях. Лошадь
        /// под всадником своя у каждого пира (Mounted едет по сети).
        void Ride()
        {
            bool riding = _character != null && _character.Mounted && _character.Alive;
            if (riding && _mount == null)
            {
                _mount = Beast.Horse(transform.parent);
                _mount.name = "Конь под седлом";
                HorseActor.Saddle(_mount.transform);
            }
            if (_mount != null) _mount.gameObject.SetActive(riding);
            if (!riding) return;
            _hips.localPosition = new Vector3(0f, Beast.HorseBack + 0.08f, -0.05f);
            for (int i = 0; i < 2; i++)
            {
                float side = i == 0 ? -1f : 1f;
                _hip[i].localRotation = Quaternion.Euler(-75f, 0f, 28f * side);
                _knee[i].localRotation = Quaternion.Euler(85f, 0f, 0f);
                if (_swing < 0f || i == 0)
                {
                    _shoulder[i].localRotation = Quaternion.Euler(-40f, 0f, 5f * side);
                    _elbow[i].localRotation = Quaternion.Euler(-45f, 0f, 0f);
                }
            }
            _torso.localRotation = Quaternion.Euler(8f, _torso.localEulerAngles.y, 0f);
        }

        void OnDestroy()
        {
            if (_mount != null) Destroy(_mount.gameObject);
        }

        static string Path(Transform t) { return t.parent == null ? t.name : Path(t.parent) + "/" + t.name; }

        static bool IsRanged(WeaponKind kind) { return kind == WeaponKind.Bow || kind == WeaponKind.Crossbow; }

        /// Отрубленная конечность исчезает; на её месте — протез ступени.
        void Wounds()
        {
            if (_character == null) return;
            var body = _character.Body;
            int severed = body.SeveredMask;
            bool changed = severed != _shownSevered;
            for (int i = 0; i < 4 && !changed; i++) if (body.Prosthetics[i] != _shownTier[i]) changed = true;
            if (!changed) return;
            _shownSevered = severed;
            for (int i = 0; i < 4; i++)
            {
                bool cut = (severed & (1 << i)) != 0;
                int tier = cut ? body.Prosthetics[i] : 0;
                _shownTier[i] = body.Prosthetics[i];
                foreach (Transform part in _limb[i]) if (part.GetComponent<MeshRenderer>() != null || part.childCount > 0) part.gameObject.SetActive(!cut);
                if (_prosthesis[i] != null) Destroy(_prosthesis[i].gameObject);
                _prosthesis[i] = null;
                if (cut && tier > 0) _prosthesis[i] = Prosthesis(_limb[i], i >= 2, tier);
            }
        }

        static readonly string[] TierMaterials = { "wood", "wood", "metal", "gold", "pale_skin" };

        Transform Prosthesis(Transform joint, bool leg, int tier)
        {
            string material = TierMaterials[Mathf.Clamp(tier, 0, TierMaterials.Length - 1)];
            float length = leg ? 0.86f : 0.56f;
            var peg = BodyShapes.Loft(leg ? "протез ноги" : "протез руки", new[]
            {
                new BodyShapes.Ring(0f, leg ? 0.06f : 0.045f, leg ? 0.06f : 0.045f), new BodyShapes.Ring(-length, 0.025f, 0.025f),
            }, 6);
            var part = BodyShapes.Part(joint, "Протез", peg, material, Vector3.zero, Vector3.one);
            // Руке — крюк на конце.
            if (!leg) BodyShapes.Part(part, "Крюк", BodyShapes.Cone(), "metal", new Vector3(0f, -length, 0.02f), new Vector3(0.05f, 0.12f, 0.05f),
                Quaternion.Euler(150f, 0f, 0f));
            return part;
        }
    }
}
