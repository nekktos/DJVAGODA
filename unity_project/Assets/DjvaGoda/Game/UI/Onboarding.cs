// Первые минуты: что делать прямо сейчас и куда для этого идти (перенос
// ui/onboarding.gd и ui/waypoint.gd).
//
// Живые отчёты Godot-версии: «не понятно что делать», «не понятно где шахта»,
// «не понятно моя зона в начале». Отсюда — цепочка шагов на сторону, на экране
// РОВНО ОДИН: ближайший невыполненный, с выгодой, клавишами (по текущей
// раскладке — после переназначения «нажми 1» врало бы) и местом. Место
// показывает метка поверх экрана: «на севере» за холмами ответ наполовину.
// В Godot это был столб света сквозь рельеф; здесь — метка на краю экрана с
// расстоянием, видна так же сквозь всё.
//
// Пройденное не откатывается: снесённый склад не вернёт к «построй склад» на
// двадцатой минуте. Необязательный шаг пропускается сам, когда его не сделать
// (нечем платить) — иначе цепочка встала бы на том, чего игрок не собирался
// делать. Последний шаг — цель партии; он не кончается и рассказывает, что
// происходит в точке захвата.
//
// Только свой: ничего не уходит в сеть и в сохранение.
using System;
using System.Collections.Generic;
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public class Onboarding : MonoBehaviour
    {
        public const float LookedAround = 40f;
        public const float Arrived = 25f;

        class Step
        {
            public string Text;
            public Func<string> Keys;
            public Func<bool> Done;
            public Func<bool> Skip;
            public string Place;
            public V3? At;
            public float Near = Arrived;
            public bool Live;
        }

        CameraRig _rig;
        PlayerCharacter _me;
        Faction _side;
        int _passed;
        bool _seenStrategy;
        V3 _spawn;
        List<Step> _chain;
        GUIStyle _title, _small;

        /// Скрыть подсказку (F1-справка, меню) — решает игрок.
        public static bool Hidden;

        public int Passed { get { return _passed; } }
        public int Total { get { return _chain != null ? _chain.Count : 0; } }
        public string CurrentText { get { return _chain != null ? LiveText(_chain[_passed]) : ""; } }
        public V3? CurrentPlace { get { return _chain != null ? _chain[_passed].At : null; } }

        void Awake() { _rig = GetComponent<CameraRig>(); }

        void Update()
        {
            var me = _rig != null ? _rig.Target : null;
            if (me == null)
            {
                _me = null;
                return;
            }
            // Сменились персонаж или сторона — цепочка заново: у сторон она своя.
            if (me != _me || me.Faction != _side)
            {
                _me = me;
                _side = me.Faction;
                _passed = 0;
                _seenStrategy = false;
                _spawn = me.Feet;
                _chain = ChainOf(_side);
            }
            if (GameMode.Strategy) _seenStrategy = true;
            while (_passed < _chain.Count - 1 && (_chain[_passed].Done() || (_chain[_passed].Skip != null && _chain[_passed].Skip())))
                _passed++;
        }

        // --- факты мира: всё, что видно и у клиента (постройки, казна, сводки NetPlayer) ---

        Wallet Wallet { get { return Treasury.Of(_me.Faction); } }

        bool Has(BuildingKind kind)
        {
            foreach (var actor in Actor.All)
            {
                var building = actor as BuildingActor;
                if (building != null && building.Alive && building.State.Done && building.Side == (int)_me.Faction && building.State.Kind == kind)
                    return true;
            }
            return false;
        }

        bool Fortified()
        {
            foreach (var actor in Actor.All)
            {
                var building = actor as BuildingActor;
                if (building != null && building.Alive && building.Side == (int)_me.Faction && building.State.Grade > 0) return true;
            }
            return false;
        }

        int SquadCount()
        {
            var net = _me.GetComponent<NetPlayer>();
            return net != null && net.IsSpawned && !net.IsServer ? net.Squad.Value & 255 : Squads.Of(_me).Count;
        }

        bool Near(V3 at, float range) { return _me.Feet.FlatDistance(at) <= range; }

        static string K(string action) { return Hud.KeyOf(action); }

        static string WalkKeys()
        {
            return K("move_forward") + K("move_left") + K("move_back") + K("move_right") + " — идти, " + K("sprint") + " — бежать, "
                + K("toggle_view") + " — от первого лица";
        }

        static string RoleKeys()
        {
            return K("role_lumberjack") + " / " + K("role_miner") + " / " + K("role_militia") + " / " + K("role_builder") + " / " + K("role_farmer");
        }

        static string Price(BuildingKind kind) { return Res.FormatCost(Res.BuildingCost(kind)); }

        static string CaptureRule()
        {
            return "держаться " + (int)MatchState.CaptureSeconds + " секунд · внутри не должно быть чужого вожака · ход захвата виден вверху";
        }

        static V3 IronMine()
        {
            for (int i = 0; i < MapLayout.Mines.Length; i++)
                if (MapLayout.Mines[i].Kind == ResourceKind.Iron) return Mines.Dock(i);
            return MapLayout.Mines[0].At;
        }

        /// Все места цепочки стороны — для проверки, что до каждой метки можно дойти.
        public List<V3> Places(Faction side)
        {
            var list = new List<V3>();
            foreach (var step in ChainOf(side)) if (step.At.HasValue) list.Add(step.At.Value);
            return list;
        }

        List<Step> ChainOf(Faction side)
        {
            if (side == Faction.Villain) return VillainChain();
            if (side == Faction.Elves) return ElfChain();
            return GuardChain();
        }

        List<Step> VillainChain()
        {
            var home = Factions.Spawn[(int)Faction.Villain];
            return new List<Step>
            {
                new Step { Text = "Ты злодей. Всё вокруг — твоя зона. Осмотрись: пробегись и оглядись", Keys = WalkKeys,
                    Done = () => !Near(_spawn, LookedAround) },
                new Step { Text = "Строить пока не на что. Набери сам: камень и золото — в микро-шахте у форта, дерево — в роще",
                    Keys = () => K("weapon_4") + " — молот, им камень бьётся вдвое · " + K("attack") + " по залежи или дереву",
                    Done = () => Wallet.CanAfford(Res.BuildingCost(BuildingKind.Storage)) || Has(BuildingKind.Storage),
                    Place = "микро-шахта", At = MapLayout.MicroMine },
                new Step { Text = "Строят и командуют СВЕРХУ. Открой вид сверху", Keys = () => K("toggle_camera"), Done = () => _seenStrategy },
                new Step { Text = "Поставь склад у базы: без него добычу некуда возить",
                    Keys = () => "сверху: " + K("build_storage") + ", затем ЛКМ по земле рядом с фортом",
                    Done = () => Has(BuildingKind.Storage), Place = "своя база", At = home },
                new Step { Text = "Найми батраков: они рубят, копают и строят сами",
                    Keys = () => "сверху: " + K("hire_labourer") + " — нанять, " + RoleKeys() + " — кем именно",
                    Done = () => Agents.CountCrew(Faction.Villain, new int[LabourerStats.RoleNames.Length]) > 0 },
                new Step { Text = "Поставь поле: еда растёт на нём сама, а фермер уносит её на склад",
                    Keys = () => "сверху: " + K("build_farm") + " — поле, нужно " + Price(BuildingKind.Farm) + " · " + K("role_farmer") + " — батрака фермером",
                    Done = () => Has(BuildingKind.Farm), Place = "своя база", At = home },
                new Step { Text = "Обозу нужна лошадь, а лошадь продают в конюшне. Поставь её и купи первую",
                    Keys = () => "сверху: " + K("build_stable") + " — конюшня, нужно " + Price(BuildingKind.Stable) + " · у конюшни " + K("interact") + " — купить лошадь",
                    Done = () => Wallet.Horses > 0, Place = "своя база", At = home },
                new Step { Text = "Железа у форта нет. Оно в железной шахте в лесу эльфов — нарисуй туда маршрут обоза",
                    Keys = () => "сверху: " + K("route") + " — рисовать, ЛКМ — точки, последняя у шахты, Enter — отправить",
                    Done = () => Wallet.GetAmount(ResourceKind.Iron) > 0, Place = "шахта", At = IronMine() },
                new Step { Text = "Воевать пока некем. Поставь казарму: бойцы берутся только из неё",
                    Keys = () => "сверху: " + K("build_sword") + " — казарма мечников, " + K("build_archer") + " — лучников · нужно " + Price(BuildingKind.SwordBarracks),
                    Done = () => Has(BuildingKind.SwordBarracks) || Has(BuildingKind.ArcherBarracks), Place = "своя база", At = home },
                new Step { Text = "Поставь дом дружины: без него сторона держит только охрану, а не войско",
                    Keys = () => "сверху: " + K("build_house") + " — дом дружины, нужно " + Price(BuildingKind.House) + " · каждый дом даёт ещё " + Res.HouseSlots + " бойцов",
                    Done = () => Squads.Capacity(Faction.Villain) > Res.SquadBase, Place = "своя база", At = home },
                new Step { Text = "Найми бойцов. Они пойдут за тобой — один ты дворец не возьмёшь",
                    Keys = () => "подойди к казарме и нажми " + K("interact") + " — там наём · отряд виден сверху",
                    Done = () => SquadCount() > 0, Place = "своя база", At = home },
                new Step { Text = "Стража приходит рано. Укрепи склад: дерево → камень → камень с железом, каждая ступень крепче",
                    Keys = () => "подойди к складу и нажми " + K("interact") + " — «укрепить», нужно " + Res.FormatCost(Res.GradeCost(BuildingKind.Storage, 0)) + " · шаг необязательный",
                    Done = Fortified, Skip = () => !Wallet.CanAfford(Res.GradeCost(BuildingKind.Storage, 0)), Place = "своя база", At = home },
                new Step { Text = "Кузня закаляет оружие за железо и уголь. Уголь — в угольной шахте в лесу эльфов, везёт обоз",
                    Keys = () => "сверху: " + K("build_forge") + " — кузня, нужно " + Price(BuildingKind.Forge) + " · у кузни " + K("interact") + " — закалить · шаг необязательный",
                    Done = () => Has(BuildingKind.Forge), Skip = () => !Wallet.CanAfford(Res.BuildingCost(BuildingKind.Forge)), Place = "своя база", At = home },
                new Step { Text = "Вот ради чего всё: дворец императора на северо-востоке. Сходи посмотри, что тебя ждёт",
                    Keys = () => "наверх ведёт пандус с юга", Done = () => Near(MatchState.Palace, 150f), Place = "дворец", At = MatchState.Palace, Near = 150f },
                new Step { Text = "В своей лавке у форта — чёрная кираса: режет урон почти на пятую часть",
                    Keys = () => K("interact") + " у прилавка · цена " + Res.FormatCost(Res.ArmorCost(Faction.Villain, 1)) + " · шаг необязательный",
                    Done = () => Near(MapLayout.Traders[(int)Faction.Villain], Shop.TraderRange),
                    Skip = () => { var price = _me.Kit.NextArmorCost(); return price.Length == 0 || !Wallet.CanAfford(price); },
                    Place = "своя лавка", At = MapLayout.Traders[(int)Faction.Villain] },
                new Step { Text = "Дворец берут не мечом, а временем: войди в ворота с юга и продержись внутри",
                    Keys = CaptureRule, Done = () => false, Live = true, Place = "дворец", At = MatchState.Palace },
            };
        }

        List<Step> ElfChain()
        {
            return new List<Step>
            {
                new Step { Text = "Ты лесной эльф. Твой лес — юго-западный угол карты. Осмотрись", Keys = WalkKeys,
                    Done = () => !Near(_spawn, LookedAround) },
                new Step { Text = "Лавка — твоя и рядом. Запомни место: сюда носить награбленное и здесь же покупать",
                    Keys = () => K("interact") + " у прилавка · денег пока нет, они с грабежа · чужие лавки тебя не обслужат",
                    Done = () => Near(MapLayout.Traders[(int)Faction.Elves], Shop.TraderRange), Place = "лавка", At = MapLayout.Traders[(int)Faction.Elves] },
                new Step { Text = "Старейшина в поселении даёт задания: засады на обозы, шахты, древние земли",
                    Keys = () => K("interact") + " у старейшины", Done = () => _me.Tasks.Task.HasValue,
                    Place = "старейшина", At = ElfTaskRecord.ElderPosition },
                new Step { Text = "Живёшь ты грабежом. Чужие обозы идут через перекрёсток в центре",
                    Keys = () => K("interact") + " у вставшей повозки — выпрячь лошадей",
                    Done = () => Near(MapLayout.Workbench, Arrived), Place = "перекрёсток", At = MapLayout.Workbench },
                new Step { Text = "Верни древние земли: уничтожь злодея и стражу. Стража — во дворце на северо-востоке",
                    Keys = () => "наверх ведёт пандус с юга · " + CaptureRule(), Done = () => false, Live = true, Place = "дворец", At = MatchState.Palace },
            };
        }

        List<Step> GuardChain()
        {
            return new List<Step>
            {
                new Step { Text = "Ты охрана дворца. Дворец рядом с тобой, и он твой", Keys = WalkKeys,
                    Done = () => !Near(_spawn, LookedAround) },
                new Step { Text = "Приказы даёт распорядитель. Подойди к нему и возьми первый",
                    Keys = () => K("interact") + " у распорядителя",
                    Done = () => _me.Service.Order.HasValue || Near(CommanderPost.Position, Orders.TalkRange),
                    Place = "распорядитель", At = CommanderPost.Position },
                new Step { Text = "Выполняй приказы: пять выполненных — командование стражей",
                    Keys = () => "текущий приказ виден над полосами здоровья", Done = () => Near(MatchState.Palace, Arrived),
                    Place = "дворец", At = MatchState.Palace },
                new Step { Text = "Не отдай дворец: взятый, он отдаст злодею всю стражу. Твоя цель — злодей и эльфы",
                    Keys = () => "чужой захват срывается только тем, что ты сам стоишь в круге: " + CaptureRule(),
                    Done = () => false, Live = true, Place = "дворец", At = MatchState.Palace },
            };
        }

        /// Последний шаг отчитывается о том, что происходит в точке захвата.
        string LiveText(Step step)
        {
            var goals = MatchGoals.Instance;
            if (!step.Live || goals == null) return step.Text;
            var state = goals.State;
            if (state.PalaceOwner == (Faction)Factions.Root((int)_me.Faction))
                return _me.Faction == Faction.Villain ? "ДВОРЕЦ ВЗЯТ: земли людей и стража теперь твои, навсегда. Дальше — вырежи эльфов"
                    : "Дворец твой, но твоя цель не в нём";
            if (state.Contested)
                return "ТОЧКА ОСПАРИВАЕТСЯ: рядом чужой вожак. Убей его или выгони за " + (int)MatchState.CaptureRadius + " м";
            if (state.CaptureProgress > 0.01f) return "Захват идёт: " + (int)(state.CaptureProgress * 100f) + "%. Не выходи из круга";
            return step.Text;
        }

        void OnGUI()
        {
            if (_me == null || _chain == null || Hidden || GameMenu.Open) return;
            if (_title == null)
            {
                _title = new GUIStyle(GUI.skin.label) { fontSize = 17, wordWrap = true, normal = { textColor = new Color(1f, 0.92f, 0.6f) } };
                _small = new GUIStyle(GUI.skin.label) { fontSize = 14, wordWrap = true };
            }
            var step = _chain[_passed];
            var box = new Rect(Screen.width - 440, Screen.height - 230, 424, 120);
            GUI.color = new Color(0f, 0f, 0f, 0.55f);
            GUI.DrawTexture(box, Texture2D.whiteTexture);
            GUI.color = Color.white;
            GUI.Label(new Rect(box.x + 8, box.y + 4, box.width - 16, 50),
                "Шаг " + (_passed + 1) + " из " + _chain.Count + ": " + LiveText(step), _title);
            string where = step.At.HasValue ? "  ·  " + step.Place + " — " + (int)_me.Feet.FlatDistance(step.At.Value) + " м" : "";
            GUI.Label(new Rect(box.x + 8, box.y + 56, box.width - 16, 60), step.Keys() + where, _small);
            if (step.At.HasValue) Marker(step.At.Value, step.Place);
        }

        /// Метка места поверх экрана; за спиной или за краем — прижата к краю.
        void Marker(V3 at, string place)
        {
            var cam = _rig.Camera;
            if (cam == null) return;
            var world = at.ToUnity() + Vector3.up * 3f;
            var screen = cam.WorldToScreenPoint(world);
            bool behind = screen.z < 0f;
            if (behind) screen = -screen;
            float x = screen.x, y = Screen.height - screen.y;
            const float pad = 40f;
            bool inside = !behind && x > pad && x < Screen.width - pad && y > pad && y < Screen.height - pad;
            if (!inside)
            {
                var centre = new Vector2(Screen.width * 0.5f, Screen.height * 0.5f);
                var dir = new Vector2(x, y) - centre;
                if (behind) dir = -dir;
                if (dir.sqrMagnitude < 1f) dir = Vector2.up;
                float scale = Mathf.Min((Screen.width * 0.5f - pad) / Mathf.Max(Mathf.Abs(dir.x), 0.01f),
                    (Screen.height * 0.5f - pad) / Mathf.Max(Mathf.Abs(dir.y), 0.01f));
                var edge = centre + dir * scale;
                x = edge.x;
                y = edge.y;
            }
            float pulse = 0.65f + 0.35f * Mathf.Sin(Time.time * Mathf.PI * 2f * 0.8f);
            GUI.color = new Color(1f, 0.85f, 0.25f, pulse);
            GUI.Label(new Rect(x - 12, y - 20, 24, 30), "◆", new GUIStyle(_title) { fontSize = 24, alignment = TextAnchor.MiddleCenter });
            GUI.Label(new Rect(x - 80, y + 6, 160, 22), place + " · " + (int)_me.Feet.FlatDistance(at) + " м",
                new GUIStyle(_small) { alignment = TextAnchor.MiddleCenter });
            GUI.color = Color.white;
        }
    }
}
