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
    public enum DealKind { Trade, Forge, Fortify, Potion, Horse }

    [RequireComponent(typeof(PlayerCharacter))]
    public class Shop : MonoBehaviour
    {
        public const float TraderRange = 7f;
        public const float BuildingReach = 4f;

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

        bool AnyPlace { get { return AtTrader || BuildingAtHand(null) != null; } }

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
                default:
                    Deals.UsePotion(_character.Kit, _character.Vitals, arg != 0);
                    return;
            }
            if (!result.Ok && !string.IsNullOrEmpty(result.Refusal) && _combat != null) _combat.Tell(result.Refusal);
        }

        void OnGUI()
        {
            if (!_character.LocalControl || GameMode.Strategy || !_character.Alive) return;
            if (!_open)
            {
                string where = AtTrader ? "лавка" : (BuildingAtHand(BuildingKind.Forge) != null && _character.Faction != Faction.Elves ? "кузня"
                    : (BuildingAtHand(null) != null ? "постройка" : null));
                if (where != null)
                    GUI.Label(new Rect(Screen.width * 0.5f - 150, Screen.height * 0.5f + 70, 300, 26), "E — " + where,
                        new GUIStyle(GUI.skin.label) { fontSize = 18, alignment = TextAnchor.MiddleCenter });
                return;
            }
            if (_style == null) _style = new GUIStyle(GUI.skin.button) { fontSize = 16, alignment = TextAnchor.MiddleLeft };
            var kit = _character.Kit;
            var wallet = Treasury.Of(_character.Faction);
            GUILayout.BeginArea(new Rect(Screen.width * 0.5f - 260, Screen.height * 0.25f, 520, 420), GUI.skin.box);
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
