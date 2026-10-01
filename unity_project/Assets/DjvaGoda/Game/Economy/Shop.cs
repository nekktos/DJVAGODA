// Сделки у места (перенос player.gd: request_trade, request_forge,
// request_upgrade_building, зелья): своя лавка, своя кузня, своя постройка.
//
// Владелец у места жмёт E — окно с товаром и ценами (мышь свободна), клик —
// заявка хосту (NetPlayer.DealRpc). Хост проверяет, что игрок у места, и
// исполняет сделку правилами ядра (Deals.Trade / ForgeGear / Fortify /
// UsePotion); отказ — владельцу на экран. Зелья — Z и X в любом месте.
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public enum DealKind { Trade, Forge, Fortify, Potion, Horse, Pickup, Workbench, Report, Promote, Mount, Caravan }

    /// Дела у верстака: arg = дело * 10 + ступень (протез) или 1/0 (коляска).
    public enum BenchOp { Prosthetic, Eye, Splint, Wheelchair }

    [RequireComponent(typeof(PlayerCharacter))]
    public class Shop : MonoBehaviour
    {
        public const float TraderRange = 7f;
        public const float BuildingReach = 4f;
        public const float BenchRange = 7f;
        /// Дальше этого лошадей у обоза не выпрягают.
        public const float RobRange = 6f;

        /// Чужой стоящий обоз рядом, с которым есть что сделать.
        public CaravanActor CartAtHand(out CaravanAction action)
        {
            action = CaravanAction.None;
            foreach (var actor in Actor.All)
            {
                var cart = actor as CaravanActor;
                if (cart == null || cart.At.FlatDistance(_character.Feet) > RobRange) continue;
                var can = cart.ActionFor(_character.Faction);
                if (can == CaravanAction.None) continue;
                action = can;
                return cart;
            }
            return null;
        }

        static readonly string[] CartVerbs = { "", "перехватить обоз", "увести лошадей", "разграбить обоз" };

        PlayerCharacter _character;
        PlayerCombat _combat;
        NetPlayer _net;
        bool _open;
        GUIStyle _style;

        void Awake()
        {
            _character = GetComponent<PlayerCharacter>();
            _combat = GetComponent<PlayerCombat>();
            _net = GetComponent<NetPlayer>();
        }

        bool Hosting { get { return _net == null || !_net.IsSpawned || _net.IsServer; } }

        public bool AtTrader { get { return MapLayout.Traders[(int)_character.Faction].FlatDistance(_character.Feet) <= TraderRange; } }

        /// Своя достроенная постройка, у которой стоишь (ближайшая); kind — только такая.
        public BuildingActor BuildingAtHand(BuildingKind? kind)
        {
            BuildingActor best = null;
            float bestGap = float.MaxValue;
            foreach (var actor in Actor.All)
            {
                var building = actor as BuildingActor;
                if (building == null || !building.Alive || !building.State.Done || building.Side != (int)_character.Faction) continue;
                if (kind.HasValue && building.State.Kind != kind.Value) continue;
                var size = Res.BuildingSize(building.State.Kind);
                float gap = building.At.FlatDistance(_character.Feet) - Mathf.Max(size.X, size.Z) * 0.5f;
                if (gap <= BuildingReach && gap < bestGap)
                {
                    bestGap = gap;
                    best = building;
                }
            }
            return best;
        }

        /// Верстак-медпункт на перекрёстке — общий для всех сторон.
        public bool AtBench { get { return MapLayout.Workbench.FlatDistance(_character.Feet) <= BenchRange; } }

        /// Оторвана конечность без протеза: деревянный ставят где угодно.
        bool NeedsWood
        {
            get
            {
                for (int i = 0; i < 4; i++)
                    if (_character.Body.IsSevered((Limb)i) && _character.Body.Tier((Limb)i) == 0) return true;
                return false;
            }
        }

        /// Свой распорядитель или старейшина рядом (живой).
        bool AtChief
        {
            get
            {
                if (_character.Faction == Faction.Guard) return Commander.Instance != null && Commander.Instance.InRange(_character.Feet);
                if (_character.Faction == Faction.Elves) return Elder.Instance != null && Elder.Instance.InRange(_character.Feet);
                return false;
            }
        }

        bool AnyPlace { get { return AtTrader || AtBench || NeedsWood || AtChief || BuildingAtHand(null) != null; } }

        bool HasOwn(BuildingKind kind)
        {
            foreach (var actor in Actor.All)
            {
                var building = actor as BuildingActor;
                if (building != null && building.Alive && building.State.Done && building.State.Kind == kind
                    && building.Side == (int)_character.Faction) return true;
            }
            return false;
        }

        void Update()
        {
            if (!_character.LocalControl || !_character.Alive || GameMode.Strategy)
            {
                Close();
                return;
            }
            if (GameInput.Pressed("potion_heal")) Ask(DealKind.Potion, 1);
            if (GameInput.Pressed("potion_mana")) Ask(DealKind.Potion, 0);
            if (_open && !AnyPlace) Close();
            // Порядок — по близости к руке: обоз, лошадь, груз под ногами, потом окна.
            if (GameInput.Pressed("interact") && !_open)
            {
                CaravanAction can = CaravanAction.None;
                if (!_character.Mounted && CartAtHand(out can) != null)
                {
                    Ask(DealKind.Caravan, 0);
                    return;
                }
                if (_character.Mounted || HorseActor.Near(_character.Feet) != null)
                {
                    Ask(DealKind.Mount, 0);
                    return;
                }
                if (Pickup.Near(_character.Feet) != null)
                {
                    Ask(DealKind.Pickup, 0);
                    return;
                }
            }
            if (GameInput.Pressed("interact") && AnyPlace)
            {
                if (_open) Close();
                else
                {
                    _open = true;
                    Cursor.lockState = CursorLockMode.None;
                    Cursor.visible = true;
                }
            }
        }

        void Close() { _open = false; }

        void Ask(DealKind deal, int arg)
        {
            if (Hosting) ServerDeal(deal, arg);
            else _net.DealRpc((int)deal, arg);
        }

        /// Сделка у хоста: место проверяет он, исполняют правила ядра.
        public void ServerDeal(DealKind deal, int arg)
        {
            if (!_character.Alive) return;
            var wallet = Treasury.Of(_character.Faction);
            Deal result;
            switch (deal)
            {
                case DealKind.Trade:
                    if (arg < 0 || arg >= System.Enum.GetValues(typeof(TradeItem)).Length) return;
                    result = Deals.Trade(_character.Kit, _character.Body, wallet, (TradeItem)arg, AtTrader);
                    break;
                case DealKind.Forge:
                    result = Deals.ForgeGear(_character.Kit, wallet, BuildingAtHand(BuildingKind.Forge) != null);
                    break;
                case DealKind.Fortify:
                    var building = BuildingAtHand(null);
                    result = Deals.Fortify(_character.Kit, wallet, building != null ? building.State : null);
                    break;
                case DealKind.Horse:
                    result = Deals.HireHorse(wallet, BuildingAtHand(BuildingKind.Stable) != null, HasOwn(BuildingKind.Stable));
                    break;
                case DealKind.Pickup:
                    TakePickup();
                    return;
                case DealKind.Mount:
                    ToggleMount();
                    return;
                case DealKind.Caravan:
                    CaravanDeal();
                    return;
                case DealKind.Report:
                    if (_character.Faction == Faction.Guard && Commander.Instance != null) Commander.Instance.Report(_character);
                    if (_character.Faction == Faction.Elves && Elder.Instance != null) Elder.Instance.Report(_character);
                    return;
                case DealKind.Promote:
                    if (Commander.Instance != null) Commander.Instance.Promote(_character);
                    return;
                case DealKind.Workbench:
                    result = Bench((BenchOp)(arg / 10), arg % 10);
                    break;
                default:
                    Deals.UsePotion(_character.Kit, _character.Vitals, arg != 0);
                    return;
            }
            if (!result.Ok && !string.IsNullOrEmpty(result.Refusal) && _combat != null) _combat.Tell(result.Refusal);
        }

        /// Поднять ближайшее (у хоста): куча — в ношу и снаряжение, конечность — в трофеи.
        void TakePickup()
        {
            var found = Pickup.Near(_character.Feet);
            if (found == null) return;
            if (found.Kind == PickupKind.Loot)
            {
                if (found.Pile == null || found.Pile.Collect(Treasury.Of(_character.Faction), _character.Kit, _character.Body) <= 0 && !found.Pile.Taken)
                {
                    if (_combat != null) _combat.Tell("взять нечего: всё своё не хуже, запас полон");
                    return;
                }
            }
            else _character.Trophies[(int)(found.Kind == PickupKind.Arm ? TrophyKind.Arms : TrophyKind.Legs)]++;
            found.Remove();
        }

        /// Сесть или спешиться — одной клавишей (у хоста).
        void ToggleMount()
        {
            if (_character.Horse != null)
            {
                _character.Horse.Dismount(_character.Feet + new V3(1.5f, 0f, 0f));
                _character.Horse = null;
                _character.Mounted = false;
                return;
            }
            var horse = HorseActor.Near(_character.Feet);
            if (horse == null || !horse.Mount(_character))
            {
                if (_combat != null) _combat.Tell("рядом нет свободной лошади");
                return;
            }
            _character.Horse = horse;
            _character.Mounted = true;
        }

        /// Увести лошадей, перехватить или разграбить стоящий чужой обоз (у хоста).
        void CaravanDeal()
        {
            CaravanAction can;
            var cart = CartAtHand(out can);
            if (cart == null || _character.Mounted)
            {
                if (_combat != null) _combat.Tell("с обозом ничего не сделать: он должен стоять и быть чужим");
                return;
            }
            var owner = (Faction)cart.Side;
            switch (can)
            {
                case CaravanAction.Intercept:
                    var storage = Builder.StorageOf(_character.Faction);
                    var nav = Object.FindAnyObjectByType<NavWorld>();
                    var walked = nav != null && nav.Ready ? nav.PathBetween(storage.At, cart.At) : null;
                    if (walked == null || walked.Count < 2) walked = new System.Collections.Generic.List<V3> { storage.At, cart.At };
                    if (!cart.Intercept(_character.Faction, OwnerId, walked)) return;
                    if (_combat != null) _combat.Tell("обоз перехвачен: едет на твой склад");
                    if (MatchGoals.Instance != null)
                        MatchGoals.Instance.Announce("Обоз «" + Factions.Names[(int)owner] + "» перехвачен стороной «" + Factions.Names[(int)_character.Faction] + "»");
                    break;
                case CaravanAction.Plunder:
                    cart.Plunder();
                    break;
                case CaravanAction.Rob:
                    if (cart.CaptureHorses() <= 0) return;
                    break;
                default:
                    return;
            }
            CaravanActor.NoteLost(cart, owner, _character);
        }

        int OwnerId { get { return _net != null && _net.IsSpawned ? (int)_net.OwnerClientId : 0; } }

        Deal Bench(BenchOp op, int param)
        {
            var body = _character.Body;
            var wallet = Treasury.Of(_character.Faction);
            switch (op)
            {
                case BenchOp.Prosthetic: return Workbench.Prosthetic(param, body, _character.Trophies, wallet, AtBench);
                case BenchOp.Eye: return Workbench.Eye(body, _character.Trophies, AtBench);
                case BenchOp.Splint: return Workbench.Splint(body, wallet, AtBench);
                default: return Workbench.Wheelchair(body, param != 0, AtBench);
            }
        }

        void ChiefPanel()
        {
            if (_character.Faction == Faction.Guard)
            {
                var service = _character.Service;
                GUILayout.Label("Распорядитель стражи — приказ: " + (service.Order.HasValue
                    ? Orders.NameOf(service.Order.Value) + " (" + Orders.ProgressText(service.Order.Value, service.Progress) + ")"
                    : "нет") + "; сдано " + service.OrdersDone);
                if (service.Order.HasValue) GUILayout.Label(Orders.BriefOf(service.Order.Value));
                if (GUILayout.Button(service.Order.HasValue ? "доложить" : "получить приказ", _style, GUILayout.Height(32))) Ask(DealKind.Report, 0);
                if (!_character.Kit.IsLeader && GUILayout.Button("принять командование (сдано " + service.OrdersDone + " из "
                    + Orders.OrdersForPromotion + ")", _style, GUILayout.Height(32))) Ask(DealKind.Promote, 0);
                return;
            }
            var tasks = _character.Tasks;
            GUILayout.Label("Старейшина — задание: " + (tasks.Task.HasValue
                ? ElfTasks.NameOf(tasks.Task.Value) + " (" + ElfTasks.ProgressText(tasks.Task.Value, tasks.Progress) + ")"
                : "нет") + "; выполнено " + tasks.TasksDone);
            if (tasks.Task.HasValue) GUILayout.Label(ElfTasks.BriefOf(tasks.Task.Value));
            if (GUILayout.Button(tasks.Task.HasValue ? "доложить" : "получить задание", _style, GUILayout.Height(32))) Ask(DealKind.Report, 0);
        }

        void BenchPanel(Wallet wallet)
        {
            var body = _character.Body;
            var t = _character.Trophies;
            GUILayout.Label((AtBench ? "Верстак-медпункт" : "Тело") + ": " + body.Summary()
                + "; трофеи — рук " + t[0] + ", ног " + t[1] + ", глаз " + t[2]);
            for (int tier = 1; tier <= BodyState.NecroticTier; tier++)
            {
                if (tier > 1 && !AtBench) break;
                bool necrotic = tier == BodyState.NecroticTier;
                var cost = necrotic ? null : Res.ProstheticCost(tier);
                if (!necrotic && cost.Length == 0) continue;
                bool any = false;
                for (int i = 0; i < 4; i++) if (body.IsSevered((Limb)i) && body.Tier((Limb)i) != tier) any = true;
                if (!any) continue;
                GUI.enabled = necrotic || wallet.CanAfford(cost);
                if (GUILayout.Button("протез: " + BodyState.TierNames[tier] + " — "
                    + (necrotic ? BodyState.NecroticPrice + " трофеев за конечность" : Res.FormatCost(cost)), _style, GUILayout.Height(32)))
                    Ask(DealKind.Workbench, (int)BenchOp.Prosthetic * 10 + tier);
                GUI.enabled = true;
            }
            if (!AtBench) return;
            if (body.EyesMissing() > 0
                && GUILayout.Button("некротический глаз — " + BodyState.NecroticPrice + " чужих глаз", _style, GUILayout.Height(32)))
                Ask(DealKind.Workbench, (int)BenchOp.Eye * 10);
            bool crippled = false;
            for (int i = 0; i < 4; i++) if (body.IsCrippled((Limb)i) && !body.IsSevered((Limb)i)) crippled = true;
            if (crippled && GUILayout.Button("вправить кость — " + Res.FormatCost(Res.SplintCost), _style, GUILayout.Height(32)))
                Ask(DealKind.Workbench, (int)BenchOp.Splint * 10);
            if (body.InWheelchair || body.IsCrawling())
                if (GUILayout.Button(body.InWheelchair ? "встать с коляски" : "сесть в коляску", _style, GUILayout.Height(32)))
                    Ask(DealKind.Workbench, (int)BenchOp.Wheelchair * 10 + (body.InWheelchair ? 0 : 1));
        }

        void OnGUI()
        {
            if (!_character.LocalControl || GameMode.Strategy || !_character.Alive) return;
            if (!_open)
            {
                var lying = Pickup.Near(_character.Feet);
                CaravanAction can = CaravanAction.None;
                var cartHere = _character.Mounted ? null : CartAtHand(out can);
                string where = cartHere != null ? CartVerbs[(int)can]
                    : _character.Mounted ? "спешиться" : HorseActor.Near(_character.Feet) != null ? "сесть на лошадь"
                    : lying != null ? "поднять: " + lying.name : AtChief ? (_character.Faction == Faction.Guard ? "распорядитель стражи" : "старейшина")
                    : AtTrader ? "лавка" : AtBench ? "верстак" : (BuildingAtHand(BuildingKind.Forge) != null && _character.Faction != Faction.Elves ? "кузня"
                    : (BuildingAtHand(null) != null ? "постройка" : NeedsWood ? "деревянный протез" : null));
                if (where != null)
                    GUI.Label(new Rect(Screen.width * 0.5f - 150, Screen.height * 0.5f + 70, 300, 26), "E — " + where,
                        new GUIStyle(GUI.skin.label) { fontSize = 18, alignment = TextAnchor.MiddleCenter });
                return;
            }
            if (_style == null) _style = new GUIStyle(GUI.skin.button) { fontSize = 16, alignment = TextAnchor.MiddleLeft };
            var kit = _character.Kit;
            var wallet = Treasury.Of(_character.Faction);
            GUILayout.BeginArea(new Rect(Screen.width * 0.5f - 260, Screen.height * 0.2f, 520, 520), GUI.skin.box);
            if (AtChief) ChiefPanel();
            if (AtBench || NeedsWood) BenchPanel(wallet);
            if (AtTrader)
            {
                GUILayout.Label("Лавка — " + Factions.Names[(int)_character.Faction] + " (E — закрыть)");
                foreach (var item in Res.Shop(_character.Faction))
                {
                    var cost = Price(item, kit);
                    string title = Title(item, kit) + (cost != null && cost.Length > 0 ? " — " + Res.FormatCost(cost) : "");
                    GUI.enabled = cost != null && cost.Length > 0 && wallet.CanAfford(cost);
                    if (GUILayout.Button(title, _style, GUILayout.Height(32))) Ask(DealKind.Trade, (int)item);
                    GUI.enabled = true;
                }
            }
            if (BuildingAtHand(BuildingKind.Forge) != null && _character.Faction != Faction.Elves)
            {
                var cost = kit.NextGearCost();
                GUILayout.Label("Кузня");
                GUI.enabled = cost.Length > 0 && wallet.CanAfford(cost);
                if (GUILayout.Button(cost.Length > 0 ? "закалить оружие: " + kit.GearTitle(kit.GearTier + 1) + " — " + Res.FormatCost(cost)
                    : "оружие закалено до предела", _style, GUILayout.Height(32))) Ask(DealKind.Forge, 0);
                GUI.enabled = true;
            }
            if (BuildingAtHand(BuildingKind.Stable) != null)
            {
                GUILayout.Label("Конюшня: лошадей " + wallet.Horses + " (в упряжке " + wallet.HorsesOut + ")");
                GUI.enabled = wallet.CanAfford(Res.HorseCost) && wallet.Horses < Res.HorseLimit;
                if (GUILayout.Button("взять лошадь — " + Res.FormatCost(Res.HorseCost), _style, GUILayout.Height(32))) Ask(DealKind.Horse, 0);
                GUI.enabled = true;
            }
            var here = BuildingAtHand(null);
            if (here != null && Factions.MayBuild(_character.Faction, here.State.Kind, kit.IsLeader))
            {
                var cost = here.State.UpgradeCost();
                GUILayout.Label(Res.BuildingNames[(int)here.State.Kind] + ": прочность " + (int)here.State.Health + " из " + (int)here.State.MaxHealth);
                GUI.enabled = cost.Length > 0 && wallet.CanAfford(cost);
                if (GUILayout.Button(cost.Length > 0 ? "укрепить на ступень — " + Res.FormatCost(cost) : "крепче не сделать",
                    _style, GUILayout.Height(32))) Ask(DealKind.Fortify, 0);
                GUI.enabled = true;
            }
            GUILayout.EndArea();
        }

        static int[] Price(TradeItem item, Kit kit)
        {
            switch (item)
            {
                case TradeItem.Bandages: return Res.BandageCost;
                case TradeItem.Arrows: return kit.ArrowPrice();
                case TradeItem.Gear: return kit.NextGearCost();
                case TradeItem.Armor: return kit.NextArmorCost();
                case TradeItem.PotionHeal: return Res.PotionHealCost;
                case TradeItem.PotionMana: return Res.PotionManaCost;
            }
            return null;
        }

        static string Title(TradeItem item, Kit kit)
        {
            switch (item)
            {
                case TradeItem.Bandages: return "бинты (+" + Res.BandagePack + ")";
                case TradeItem.Arrows: return "стрелы (+" + Res.ArrowPack + ", сейчас " + kit.Arrows + ")";
                case TradeItem.Gear: return "оружие: " + kit.GearTitle(kit.GearTier + 1);
                case TradeItem.Armor: return "доспех: " + Res.ArmorName(kit.Side, kit.ArmorTier + 1);
                case TradeItem.PotionHeal: return "зелье лечения (" + kit.PotionsHeal + " из " + Res.PotionLimit + ")";
                case TradeItem.PotionMana: return "зелье маны (" + kit.PotionsMana + " из " + Res.PotionLimit + ")";
            }
            return item.ToString();
        }
    }
}
