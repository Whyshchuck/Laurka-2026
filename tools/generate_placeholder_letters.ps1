# Generator tymczasowych literek-placeholderow do res://letters/.
# Docelowo zastapia je skany rysunkow dzieci (to samo nazewnictwo!).
# Uzycie:  powershell -File tools\generate_placeholder_letters.ps1
# (Plik celowo bez polskich znakow - PowerShell 5.1 czyta .ps1 bez BOM jako ANSI.)
param([string]$OutDir = "$PSScriptRoot\..\letters")

$src = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.IO;
using System.Runtime.InteropServices;

public static class LetterGen
{
    // Kody polskich znakow w nazwach plikow (patrz letters/README.md)
    static readonly Dictionary<char, string> Codes = new Dictionary<char, string>
    {
        { 'ą', "a_pol" }, { 'ć', "c_pol" }, { 'ę', "e_pol" },
        { 'ł', "l_pol" }, { 'ń', "n_pol" }, { 'ó', "o_pol" },
        { 'ś', "s_pol" }, { 'ż', "z_pol" }, { 'ź', "zi_pol" },
        { '?', "pytajnik" }, { '!', "wykrzyknik" }
    };

    public static int Run(string outDir)
    {
        string chars = "abcdefghijklmnopqrstuvwxyz0123456789"
            + "ąćęłńóśźż" + "?!";
        // 3 "odreczne" fonty = 3 warianty kazdej literki
        string[] fonts = { "Segoe Print", "Ink Free", "Comic Sans MS" };
        Color[] palette =
        {
            Color.FromArgb(214, 69, 65),   // czerwona kredka
            Color.FromArgb(31, 119, 180),  // niebieska
            Color.FromArgb(44, 160, 44),   // zielona
            Color.FromArgb(255, 127, 14),  // pomaranczowa
            Color.FromArgb(148, 103, 189), // fioletowa
            Color.FromArgb(140, 86, 75)    // brazowa
        };
        var rnd = new Random(2026);
        Directory.CreateDirectory(outDir);
        int count = 0;

        foreach (char c in chars)
        {
            string code = Codes.ContainsKey(c) ? Codes[c] : c.ToString();
            for (int v = 0; v < fonts.Length; v++)
            {
                using (var bmp = new Bitmap(600, 600, PixelFormat.Format32bppArgb))
                using (var g = Graphics.FromImage(bmp))
                using (var font = new Font(fonts[v], 170f, FontStyle.Regular, GraphicsUnit.Point))
                using (var brush = new SolidBrush(palette[rnd.Next(palette.Length)]))
                {
                    g.SmoothingMode = SmoothingMode.AntiAlias;
                    g.TextRenderingHint = TextRenderingHint.AntiAlias;
                    g.TranslateTransform(300f, 300f);
                    g.RotateTransform((float)(rnd.NextDouble() * 16.0 - 8.0)); // lekki "dzieciecy" przechyl
                    var size = g.MeasureString(c.ToString(), font);
                    g.DrawString(c.ToString(), font, brush, -size.Width / 2f, -size.Height / 2f);
                    g.ResetTransform();

                    Rectangle bounds = FindBounds(bmp);
                    if (bounds.Width <= 0 || bounds.Height <= 0) continue;
                    using (var cropped = bmp.Clone(bounds, PixelFormat.Format32bppArgb))
                    {
                        string path = Path.Combine(outDir, code + "_" + (v + 1) + ".png");
                        cropped.Save(path, ImageFormat.Png);
                        count++;
                    }
                }
            }
        }
        return count;
    }

    // Przyciecie do faktycznej zawartosci (alpha > 16) z malym marginesem
    static Rectangle FindBounds(Bitmap bmp)
    {
        var data = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height),
            ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        var buf = new byte[data.Stride * bmp.Height];
        Marshal.Copy(data.Scan0, buf, 0, buf.Length);
        bmp.UnlockBits(data);

        int minX = bmp.Width, minY = bmp.Height, maxX = -1, maxY = -1;
        for (int y = 0; y < bmp.Height; y++)
        {
            int row = y * data.Stride;
            for (int x = 0; x < bmp.Width; x++)
            {
                if (buf[row + x * 4 + 3] > 16)
                {
                    if (x < minX) minX = x;
                    if (x > maxX) maxX = x;
                    if (y < minY) minY = y;
                    if (y > maxY) maxY = y;
                }
            }
        }
        if (maxX < 0) return Rectangle.Empty;
        int pad = 3;
        minX = Math.Max(0, minX - pad); minY = Math.Max(0, minY - pad);
        maxX = Math.Min(bmp.Width - 1, maxX + pad); maxY = Math.Min(bmp.Height - 1, maxY + pad);
        return new Rectangle(minX, minY, maxX - minX + 1, maxY - minY + 1);
    }
}
'@

Add-Type -TypeDefinition $src -ReferencedAssemblies System.Drawing
$resolved = (Resolve-Path $OutDir).Path
$n = [LetterGen]::Run($resolved)
Write-Output "Wygenerowano $n plikow do: $resolved"
