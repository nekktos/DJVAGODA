// Загрузчик сцены: мир из ядра, персонаж на точке своей стороны, камера.
//
// Одиночно (Networked = false) персонаж ставится сразу — так его гоняют
// проверки ходьбы. В сетевой сцене персонажей спавнит хост (NetSession), а
// загрузчик строит только мир и камеру без цели.
using DjvaGoda.Core;
using UnityEngine;

namespace DjvaGoda.Game
{
    public class Bootstrap : MonoBehaviour
    {
        public Faction Side = Faction.Guard;
        public bool Networked;

        public WorldBuilder World { get; private set; }
        public NavWorld Nav { get; private set; }
        public PlayerCharacter Player { get; private set; }
        public CameraRig Rig { get; private set; }

        void Awake()
        {
            World = new GameObject("Мир").AddComponent<WorldBuilder>();
            // Сетка печётся в Start — после того, как мир построился в Awake.
            Nav = World.gameObject.AddComponent<NavWorld>();
            Light();

            var eye = new GameObject("Камера");
            eye.tag = "MainCamera";
            Rig = eye.AddComponent<CameraRig>();
            if (Networked) return;

            var root = new GameObject("Игрок");
            root.transform.position = (Factions.Spawn[(int)Side] + new V3(0f, 1f, 0f)).ToUnity();
            AddBody(root.transform, Side);
            Player = root.AddComponent<PlayerCharacter>();
            Player.Faction = Side;
            Rig.Target = Player;
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

        static void Light()
        {
            if (Object.FindAnyObjectByType<Light>() != null) return;
            var sun = new GameObject("Солнце").AddComponent<Light>();
            sun.type = LightType.Directional;
            sun.intensity = 1.1f;
            sun.shadows = LightShadows.Soft;
            sun.transform.rotation = Quaternion.Euler(50f, -30f, 0f);
        }
    }
}
