// Сохранение мира (перенос savegame.gd). Схема — SaveData ядра; здесь —
// снять мир в неё, записать JSON и поднять обратно.
//
// Сохраняет и загружает ТОЛЬКО хост: у клиента нет авторитетного состояния,
// его файл был бы копией чужой правды. Мир — по номеру мира хозяина
// (persistentDataPath/world.cfg, или ключ -world=ID); -freshworld — не читать
// и не писать (проверки, чистые прогоны).
//
// Что сохраняется: исход партии, казна сторон, постройки, батраки, прогресс
// людей по паре ПРОФИЛЬ + СТОРОНА (снаряжение, ранения, трофеи, служба,
// уровни). Что НЕТ — намеренно: позиции, снаряды, кучи на земле: это
// состояние боя, а не прогресса; люди встают на базах своей стороны.
//
// Когда: раз в минуту, при уходе игрока (его книжка), при остановке хоста и
// выходе из игры.
using System;
using System.Collections.Generic;
using System.IO;
using DjvaGoda.Core;
using Unity.Netcode;
using UnityEngine;

namespace DjvaGoda.Game
{
    public class SaveGame : MonoBehaviour
    {
        public static SaveGame Instance { get; private set; }

        public const float AutosaveInterval = 60f;

        public string WorldId;
        /// Не читать и не писать: -freshworld или проверки.
        public bool Frozen;
        /// Каталог сохранений (проверки подменяют на временный).
        public string Folder;

        SaveData _data;
        bool _loaded;
        float _autosave;
        readonly HashSet<string> _restored = new HashSet<string>();

        void Awake()
        {
            Instance = this;
            Folder = Path.Combine(Application.persistentDataPath, "saves");
            // В редакторе мир не пишется и не читается: проверки и отладочные
            // партии не должны ни портить, ни подхватывать настоящие сохранения.
            Frozen = Application.isEditor;
            foreach (var arg in Environment.GetCommandLineArgs())
            {
                if (arg == "-freshworld") Frozen = true;
                if (arg.StartsWith("-world=")) WorldId = arg.Substring("-world=".Length);
            }
            if (string.IsNullOrEmpty(WorldId)) WorldId = Frozen ? "редактор" : LoadOrMakeWorldId();
        }

        void OnEnable()
        {
            if (NetworkManager.Singleton != null) NetworkManager.Singleton.OnServerStopped += OnServerStopped;
        }

        void OnDisable()
        {
            if (NetworkManager.Singleton != null) NetworkManager.Singleton.OnServerStopped -= OnServerStopped;
            if (Instance == this) Instance = null;
        }

        static string LoadOrMakeWorldId()
        {
            var path = Path.Combine(Application.persistentDataPath, "world.cfg");
            try
            {
                if (File.Exists(path))
                {
                    var id = File.ReadAllText(path).Trim();
                    if (id.Length > 0) return id;
                }
                var made = "мир-" + DateTime.Now.ToString("yyyyMMdd-HHmmss");
                File.WriteAllText(path, made);
                return made;
            }
            catch (Exception e)
            {
                Debug.LogWarning("[сохранение] номер мира не прочитан: " + e.Message);
                return "мир";
            }
        }

        public string PathOf { get { return Path.Combine(Folder, WorldId + ".json"); } }

        static bool Hosting
        {
            get
            {
                var net = NetworkManager.Singleton;
                if (net != null && net.IsListening) return net.IsServer;
                var goals = MatchGoals.Instance;
                return goals != null && goals.RunWithoutNetwork;
            }
        }

        void Update()
        {
            if (!Hosting || Frozen) return;
            _autosave += Time.deltaTime;
            if (_autosave < AutosaveInterval) return;
            _autosave = 0f;
            Save();
        }

        void OnServerStopped(bool wasHost) { Save(); }

        void OnApplicationQuit() { if (Hosting) Save(); }

        /// Сохранение с диска (один раз за партию); нет файла — null.
        SaveData Data
        {
            get
            {
                if (_loaded) return _data;
                _loaded = true;
                if (Frozen || !File.Exists(PathOf)) return null;
                try
                {
                    _data = JsonUtility.FromJson<SaveData>(File.ReadAllText(PathOf));
                }
                catch (Exception e)
                {
                    Debug.LogWarning("[сохранение] не прочитано " + PathOf + ": " + e.Message);
                    _data = null;
                }
                return _data;
            }
        }

        // --- запись ------------------------------------------------------------

        /// Записать мир (хост). Возвращает путь или пустую строку.
        public string Save()
        {
            if (Frozen) return "";
            var data = Data ?? new SaveData();
            // Сразу в память: Remember ниже пишет людей в этот же экземпляр.
            _data = data;
            _loaded = true;
            data.worldId = WorldId;
            data.savedAt = DateTime.Now.ToString("s");
            if (MatchGoals.Instance != null) data.CaptureMatch(MatchGoals.Instance.State);
            data.treasuries.Clear();
            for (int side = 0; side < Factions.Count; side++) data.treasuries.Add(SaveData.CaptureTreasury((Faction)side, Treasury.Of(side)));
            data.buildings.Clear();
            data.labourers.Clear();
            foreach (var actor in Actor.All)
            {
                var building = actor as BuildingActor;
                if (building != null && building.Alive)
                {
                    var at = building.At;
                    data.buildings.Add(new SavedBuilding
                    {
                        kind = (int)building.State.Kind, x = at.X, y = at.Y, z = at.Z,
                        faction = building.Side, owner = building.Side,
                        progress = building.State.Progress, health = building.State.Health, grade = building.State.Grade,
                    });
                    continue;
                }
                var worker = actor as LabourerAgent;
                if (worker != null && worker.Alive && worker.Brain != null)
                    data.labourers.Add(new SavedLabourer
                    {
                        faction = (int)worker.Brain.Side, role = (int)worker.Brain.Role,
                        homeX = worker.Home.X, homeY = worker.Home.Y, homeZ = worker.Home.Z,
                    });
                var player = actor as PlayerCharacter;
                if (player != null) Remember(player);
            }
            try
            {
                Directory.CreateDirectory(Folder);
                File.WriteAllText(PathOf, JsonUtility.ToJson(data, true));
            }
            catch (Exception e)
            {
                Debug.LogWarning("[сохранение] не записано " + PathOf + ": " + e.Message);
                return "";
            }
            Debug.Log("[сохранение] мир " + WorldId + ": построек " + data.buildings.Count + ", батраков " + data.labourers.Count
                + ", игроков " + data.players.Count);
            return PathOf;
        }

        /// Снять прогресс человека в сохранение (без записи на диск): при
        /// каждом сохранении и при его уходе из сессии.
        public void Remember(PlayerCharacter player)
        {
            if (Frozen || string.IsNullOrEmpty(player.Profile)) return;
            if (_data == null)
            {
                _data = Data ?? new SaveData();
                _loaded = true;
            }
            var saved = Find(player.Profile, (int)player.Faction);
            if (saved == null)
            {
                saved = new SavedPlayer { profile = player.Profile, faction = (int)player.Faction };
                _data.players.Add(saved);
            }
            var kit = player.Kit;
            var body = player.Body;
            saved.gearTier = kit.GearTier;
            saved.armorTier = kit.ArmorTier;
            saved.potionsHeal = kit.PotionsHeal;
            saved.potionsMana = kit.PotionsMana;
            saved.isLeader = kit.IsLeader;
            saved.ordersDone = player.Service.OrdersDone;
            saved.finalThreshold = player.Service.FinalThreshold;
            saved.alive = player.Alive || !kit.IsLeader;
            saved.severedMask = body.SeveredMask;
            saved.crippledMask = body.CrippledMask;
            saved.prosthetics = (int[])body.Prosthetics.Clone();
            saved.eyesLost = body.EyesLost;
            saved.eyeImplants = body.EyeImplants;
            saved.trophies = (int[])player.Trophies.Clone();
            saved.bandages = body.Bandages;
            saved.inWheelchair = body.InWheelchair;
            saved.experience = player.Vitals.Experience;
            saved.upgrades = (int[])player.Vitals.Levels.Clone();
        }

        SavedPlayer Find(string profile, int faction)
        {
            if (_data == null) return null;
            foreach (var saved in _data.players)
                if (saved.profile == profile && saved.faction == faction) return saved;
            return null;
        }

        // --- загрузка ----------------------------------------------------------

        /// Поднять мир (хост, старт партии). true — сохранение было: постройки
        /// из него, стартовые не ставить.
        public bool LoadWorld()
        {
            var data = Data;
            if (data == null) return false;
            if (MatchGoals.Instance != null) data.RestoreMatch(MatchGoals.Instance.State);
            foreach (var saved in data.treasuries)
                if (saved.faction >= 0 && saved.faction < Factions.Count) SaveData.RestoreTreasury(saved, Treasury.Of(saved.faction));
            var nav = UnityEngine.Object.FindAnyObjectByType<NavWorld>();
            foreach (var saved in data.buildings)
            {
                if (saved.kind < 0 || saved.kind >= Res.BuildingNames.Length || saved.faction < 0 || saved.faction >= Factions.Count) continue;
                var building = BuildingActor.Spawn((BuildingKind)saved.kind, (Faction)saved.faction, new V3(saved.x, saved.y, saved.z), false, nav);
                building.State.Progress = saved.progress;
                building.State.Grade = saved.grade;
                building.State.Health = saved.health;
                // Склад уже поднял потолок в сохранённой казне: второй раз не поднимать.
                building.MarkCompleted();
            }
            var count = new int[Factions.Count];
            foreach (var saved in data.labourers)
            {
                if (saved.faction < 0 || saved.faction >= Factions.Count) continue;
                Builder.SpawnLabourer((Faction)saved.faction, (LabourerRole)Mathf.Clamp(saved.role, 0, LabourerStats.RoleNames.Length - 1),
                    count[saved.faction]++);
            }
            Debug.Log("[сохранение] мир " + WorldId + " поднят: построек " + data.buildings.Count + ", батраков " + data.labourers.Count);
            return true;
        }

        /// Вернуть человеку нажитое за эту сторону — однажды за сессию.
        public bool RestorePlayer(PlayerCharacter player)
        {
            if (string.IsNullOrEmpty(player.Profile)) return false;
            string key = player.Profile + "|" + (int)player.Faction;
            if (_restored.Contains(key)) return false;
            var saved = Data != null ? Find(player.Profile, (int)player.Faction) : null;
            if (saved == null) return false;
            _restored.Add(key);
            var kit = player.Kit;
            var body = player.Body;
            kit.GearTier = saved.gearTier;
            kit.ArmorTier = saved.armorTier;
            kit.PotionsHeal = saved.potionsHeal;
            kit.PotionsMana = saved.potionsMana;
            kit.IsLeader = saved.isLeader;
            player.Service.IsLeader = saved.isLeader && player.Faction == Faction.Guard;
            player.Service.OrdersDone = saved.ordersDone;
            player.Service.FinalThreshold = saved.finalThreshold;
            body.SeveredMask = saved.severedMask;
            body.CrippledMask = saved.crippledMask;
            for (int i = 0; i < 4 && i < saved.prosthetics.Length; i++) body.Prosthetics[i] = saved.prosthetics[i];
            body.EyesLost = saved.eyesLost;
            body.EyeImplants = saved.eyeImplants;
            for (int i = 0; i < 3 && i < saved.trophies.Length; i++) player.Trophies[i] = saved.trophies[i];
            body.Bandages = saved.bandages;
            body.InWheelchair = saved.inWheelchair;
            player.Vitals.Experience = saved.experience;
            for (int i = 0; i < 4 && i < saved.upgrades.Length; i++) player.Vitals.Levels[i] = saved.upgrades[i];
            player.Vitals.Revive();
            // Павший вожак не встаёт и после перезахода: его смерть окончательна.
            if (!saved.alive) player.Vitals.Alive = false;
            Debug.Log("[сохранение] игроку " + player.Profile + " возвращено нажитое за " + Factions.Names[(int)player.Faction]);
            return true;
        }
    }
}
