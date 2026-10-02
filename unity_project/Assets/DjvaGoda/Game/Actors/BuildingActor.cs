// Постройка в мире (перенос economy/building.gd): состояние — BuildingState
// ядра (стройка, ступени, урон с правилом стражи), вид — своя модель
// (BuildingShapes): стены по ступени укрепления, крыша, приметы вида;
// недостроенная — леса и растущие стены. Твёрдая постройка
// вырезает себя из запечённой сетки навигации (NavMeshObstacle), снесённая —
// возвращает место.
//
// Считает хост: стройку, поле, урон. По сети постройка — префаб
// Resources/Building с NetworkObject, состояние клиентам везёт BuildingNet.
// Без сети (проверки, одиночный загрузчик) — простой объект.
using DjvaGoda.Core;
using Unity.Netcode;
using UnityEngine;
using UnityEngine.AI;

namespace DjvaGoda.Game
{
    public class BuildingActor : Actor
    {
        public BuildingState State;
        public NavWorld Nav;
        Transform _view;
        int _shownGrade = -1;
        bool _wasDone;
        bool _completed;
        /// Строители у стройки: номер батрака → сколько ещё помнить (как копатели шахты).
        readonly System.Collections.Generic.Dictionary<int, float> _builders = new System.Collections.Generic.Dictionary<int, float>();
        public const float BuilderMemory = 3f;

        /// Сколько строителей сейчас у стройки.
        public int BuildersNow { get { return _builders.Count; } }

        /// Батрак-строитель ударил у стройки.
        public void NoteBuilder(int workerId) { _builders[workerId] = BuilderMemory; }

        int Builders(float delta)
        {
            var keys = new System.Collections.Generic.List<int>(_builders.Keys);
            foreach (var id in keys)
            {
                _builders[id] -= delta;
                if (_builders[id] <= 0f) _builders.Remove(id);
            }
            return _builders.Count;
        }

        public override bool Alive { get { return State != null && !State.Destroyed; } }
        public override BuildingKind? Building { get { return State != null ? State.Kind : (BuildingKind?)null; } }

        static GameObject _prefab;

        /// Хост (или машина без сети) ставит постройку.
        public static BuildingActor Spawn(BuildingKind kind, Faction side, V3 at, bool prebuilt, NavWorld nav)
        {
            var net = NetworkManager.Singleton;
            if (net != null && net.IsListening && net.IsServer)
            {
                if (_prefab == null) _prefab = Resources.Load<GameObject>("Building");
                var go = Instantiate(_prefab, at.ToUnity(), Quaternion.identity);
                var actor = go.GetComponent<BuildingActor>();
                actor.Init(kind, side, prebuilt);
                actor.Nav = nav;
                go.GetComponent<NetworkObject>().Spawn();
                return actor;
            }
            var local = new GameObject(Res.BuildingNames[(int)kind]);
            local.transform.position = at.ToUnity();
            var made = local.AddComponent<BuildingActor>();
            made.Init(kind, side, prebuilt);
            made.Nav = nav;
            return made;
        }

        /// Задать постройку: у хоста — при спавне, у клиента — по BuildingNet.
        public void Init(BuildingKind kind, Faction side, bool prebuilt)
        {
            State = new BuildingState(kind, side, prebuilt);
            Side = (int)side;
            name = Res.BuildingNames[(int)kind] + " (" + Factions.Names[(int)side] + ")";
            var size = Res.BuildingSize(kind).ToUnity();
            if (!Res.Walkable(kind)) Carve(size);
            Zone(size);
            Rebuild();
        }

        /// Хозяин партии считает стройку и поле.
        static bool Hosting
        {
            get
            {
                var net = NetworkManager.Singleton;
                return net == null || !net.IsListening || net.IsServer;
            }
        }

        /// Зона попадания во всю коробку: постройку бьют тем же оружием.
        void Zone(Vector3 size)
        {
            var go = new GameObject("Зона попадания");
            go.layer = HitZone.Layer;
            go.transform.SetParent(transform, false);
            go.transform.localPosition = new Vector3(0f, size.y * 0.5f, 0f);
            var box = go.AddComponent<BoxCollider>();
            box.isTrigger = true;
            box.size = size;
            var zone = go.AddComponent<HitZone>();
            zone.Zone = "torso";
            zone.Owner = this;
        }

        void Rebuild()
        {
            if (_view != null) Destroy(_view.gameObject);
            // Модель по виду и ступени (BuildingShapes); недостроенная — леса и стены без крыши.
            _view = BuildingShapes.Build(transform, State.Kind, State.Grade, State.Side, State.Done);
            _walls = _view.Find(BuildingShapes.WallsName);
            _shownGrade = State.Grade;
            _wasDone = State.Done;
            ShowProgress(Res.BuildingSize(State.Kind).ToUnity());
        }

        Transform _walls;

        /// Недостроенная — стены растут с ходом стройки: видно, сколько осталось.
        void ShowProgress(Vector3 size)
        {
            if (_walls == null) return;
            float height = State.Done ? 1f : Mathf.Max(0.12f, State.Progress);
            _walls.localScale = new Vector3(1f, height, 1f);
        }

        /// Вырез в сетке во всю постройку (а не по недостроенной высоте):
        /// стройку тоже обходят. Вырез только у стоящего — постройки не ездят.
        void Carve(Vector3 size)
        {
            var obstacle = GetComponent<NavMeshObstacle>();
            if (obstacle == null) obstacle = gameObject.AddComponent<NavMeshObstacle>();
            obstacle.shape = NavMeshObstacleShape.Box;
            obstacle.size = size;
            obstacle.center = new Vector3(0f, size.y * 0.5f, 0f);
            obstacle.carving = true;
            obstacle.carveOnlyStationary = true;
        }

        void Update()
        {
            if (State == null) return;
            if (Hosting)
            {
                // Хозяин строит сам; каждый строитель-батрак у стройки прибавляет долю.
                State.Build(Time.deltaTime, Builders(Time.deltaTime));
                if (State.Done) State.Grow(Time.deltaTime);
                if (State.Done && !_completed) Completed();
            }
            if (State.Grade != _shownGrade || State.Done != _wasDone) Rebuild();
            else if (!State.Done) ShowProgress(Res.BuildingSize(State.Kind).ToUnity());
        }

        /// Поднята из сохранения: казна уже помнит её склад — не поднимать потолок ещё раз.
        public void MarkCompleted() { _completed = State.Done; }

        /// Достроена (у хоста): склад поднимает стороне потолок хранения — и
        /// построенный игроком, и поставленный ИИ.
        void Completed()
        {
            _completed = true;
            if (State.Kind == BuildingKind.Storage) Treasury.Of(State.Side).RaiseCapacity(Res.StorageBonus);
        }

        public override void TakeDamage(float amount, string zone, WeaponKind? weapon, bool aoe, Actor source)
        {
            if (!Alive) return;
            int gear = 0, armor = 0;
            var hitter = source as PlayerCharacter;
            if (hitter != null)
            {
                gear = hitter.Kit.GearTier;
                armor = hitter.Kit.ArmorTier;
            }
            State.TakeDamage(amount, source != null ? source.Side : -1, gear, armor);
            if (Alive) return;
            var net = GetComponent<NetworkObject>();
            if (net != null && net.IsSpawned) net.Despawn(true);
            else Destroy(gameObject);
        }
    }
}
