// Иконки интерфейса (свои, кодом: Editor/IconBake) — из Resources/Icons по имени.
// Нет файла — null, и HUD рисует подпись без картинки.
using System.Collections.Generic;
using UnityEngine;

namespace DjvaGoda.Game
{
    public static class Icons
    {
        static readonly Dictionary<string, Texture2D> Cache = new Dictionary<string, Texture2D>();

        public static Texture2D Get(string name)
        {
            Texture2D texture;
            if (Cache.TryGetValue(name, out texture)) return texture;
            texture = Resources.Load<Texture2D>("Icons/" + name);
            Cache[name] = texture;
            return texture;
        }

        /// Иконка в прямоугольнике; полупрозрачная — когда недоступно.
        public static void Draw(Rect rect, string name, bool dim = false)
        {
            var texture = Get(name);
            if (texture == null) return;
            var keep = GUI.color;
            if (dim) GUI.color = new Color(keep.r, keep.g, keep.b, keep.a * 0.45f);
            GUI.DrawTexture(rect, texture, ScaleMode.ScaleToFit, true);
            GUI.color = keep;
        }
    }
}
