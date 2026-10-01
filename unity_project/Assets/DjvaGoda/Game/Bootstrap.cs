// Загрузчик сцены: находит мир (собран в редакторе и лежит в сцене), ставит
// камеру и — в одиночном режиме — персонажа на точке своей стороны.
//
// В сетевой сцене (Networked) персонажей спавнит хост (NetSession), камера
// ждёт своего. Проверки ходьбы берут сетевую сцену и ставят персонажа сами
// (SpawnLocal).
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public class Bootstrap : MonoBehaviour
    {
        public Faction Side = Faction.Guard;
        public bool Networked;

        public World World { get; private set; }
        public NavWorld Nav { get; private set; }
        public PlayerCharacter Player { get; private set; }
        public CameraRig Rig { get; private set; }

        void Awake()
        {
            World = Object.FindAnyObjectByType<World>();
            if (World == null) Debug.LogError("В сцене нет мира: ДжваГода → Собрать мир.");
            else Nav = World.GetComponent<NavWorld>();

            var eye = new GameObject("Камера");
            eye.tag = "MainCamera";
            Rig = eye.AddComponent<CameraRig>();
            if (!Networked) SpawnLocal(Side);
        }

        /// Персонаж без сети — на точке стороны, под камерой.
        public PlayerCharacter SpawnLocal(Faction side)
        {
            var root = new GameObject("Игрок");
            root.transform.position = (Factions.Spawn[(int)side] + new V3(0f, 1f, 0f)).ToUnity();
            AddBody(root.transform, side);
            Player = root.AddComponent<PlayerCharacter>();
            Player.Faction = side;
            Rig.Target = Player;
            return Player;
        }

        /// Капсула-заглушка цвета стороны — отдельным телом: у примитива центр
        /// посередине, а коллайдер персонажа (CharacterController) стоит от ног вверх.
        public static void AddBody(Transform root, Faction side)
        {
            var body = GameObject.CreatePrimitive(PrimitiveType.Capsule);
            body.name = "Тело";
            var capsule = body.GetComponent<CapsuleCollider>();
            if (capsule != null) Destroy(capsule);
            body.transform.SetParent(root, false);
            body.transform.localPosition = new Vector3(0f, 0.9f, 0f);
            body.transform.localScale = new Vector3(0.7f, 0.9f, 0.7f);
            var view = body.GetComponent<MeshRenderer>();
            if (view != null) view.sharedMaterial = Palette.Side(side);
        }
    }
}
