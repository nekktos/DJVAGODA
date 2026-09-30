// Постройка в мире (перенос economy/building.gd): состояние — BuildingState
// ядра (стройка, ступени, урон с правилом стражи), вид — серая коробка
// размером с постройку. Встала или снесена — сетка навигации перепекается.
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public class BuildingActor : Actor
    {
        public BuildingState State;
        public NavWorld Nav;
        Transform _view;
        int _shownGrade = -1;
        bool _wasDone;

        public override bool Alive { get { return State != null && !State.Destroyed; } }
        public override BuildingKind? Building { get { return State != null ? State.Kind : (BuildingKind?)null; } }

        public static BuildingActor Spawn(BuildingKind kind, Faction side, V3 at, bool prebuilt, NavWorld nav)
        {
            var go = new GameObject(Res.BuildingNames[(int)kind]);
            go.transform.position = at.ToUnity();
            var actor = go.AddComponent<BuildingActor>();
            actor.State = new BuildingState(kind, side, prebuilt);
            actor.Side = (int)side;
            actor.Nav = nav;
            actor.Rebuild();
            if (nav != null) nav.MarkDirty();
            return actor;
        }

        void Rebuild()
        {
            if (_view != null) Destroy(_view.gameObject);
            var size = Res.BuildingSize(State.Kind).SizeToUnity();
            var box = GameObject.CreatePrimitive(PrimitiveType.Cube);
            box.name = "Вид";
            box.transform.SetParent(transform, false);
            // Недостроенная — по пояс: видно, сколько осталось.
            float height = size.y * (State.Done ? 1f : Mathf.Max(0.15f, State.Progress));
            box.transform.localScale = new Vector3(size.x, height, size.z);
            box.transform.localPosition = new Vector3(0f, height * 0.5f, 0f);
            var grade = State.Grade <= 0 ? "wood" : (State.Grade == 1 ? "stone" : "dark_stone");
            box.GetComponent<MeshRenderer>().sharedMaterial = Palette.Of(grade);
            // Поле проходимо: без коллизии.
            if (Res.Walkable(State.Kind)) Destroy(box.GetComponent<Collider>());
            _view = box.transform;
            _shownGrade = State.Grade;
            _wasDone = State.Done;
        }

        void Update()
        {
            if (State == null) return;
            if (State.Grade != _shownGrade || State.Done != _wasDone) Rebuild();
            if (State.Done) State.Grow(Time.deltaTime);
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
            if (!Alive)
            {
                if (Nav != null) Nav.MarkDirty();
                Destroy(gameObject);
            }
        }
    }
}
