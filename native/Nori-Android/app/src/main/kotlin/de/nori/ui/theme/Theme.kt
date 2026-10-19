package de.nori.ui.theme

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Nori-Farben, Zahl für Zahl aus `Theme.swift` der Apple-Apps.
 *
 * Nicht neu erfunden und nicht aus Material abgeleitet: die App soll auf
 * Android dieselbe sein. Das Blaugrau ist bewusst sehr dunkel — vor einem
 * Video ist jedes hellere Grau eine Störung.
 */
object NoriColors {
    val bg = Color(0xFF05060A)
    val surface = Color(0xFF0C0E14)
    val elevated = Color(0xFF141822)
    val fg = Color(0xFFEEF1F6)
    val muted = Color(0xFF8B93A7)
    val accent = Color(0xFFD7DEEA)
    val border = Color(0x14FFFFFF)

    /** Für Fehlermeldungen und den „nicht abspielbar"-Fall. */
    val danger = Color(0xFFE5646E)
    /** Fortschrittsbalken auf Kacheln. */
    val progress = Color(0xFF7FB4FF)
}

/**
 * Ein einziges, dunkles Erscheinungsbild.
 *
 * Material 3 wäre in der Lage, sich am Systemthema zu orientieren — die App
 * folgt dem bewusst nicht. Nori ist eine Video-App; ein heller Modus mit
 * weißen Flächen neben einem laufenden Film ist kein Zustand, den jemand
 * haben will, und die Apple-Fassungen kennen ihn auch nicht.
 */
private val NoriScheme = darkColorScheme(
    primary = NoriColors.accent,
    onPrimary = NoriColors.bg,
    primaryContainer = NoriColors.elevated,
    onPrimaryContainer = NoriColors.fg,
    secondary = NoriColors.muted,
    onSecondary = NoriColors.bg,
    background = NoriColors.bg,
    onBackground = NoriColors.fg,
    surface = NoriColors.surface,
    onSurface = NoriColors.fg,
    surfaceVariant = NoriColors.elevated,
    onSurfaceVariant = NoriColors.muted,
    surfaceContainer = NoriColors.elevated,
    surfaceContainerHigh = NoriColors.elevated,
    surfaceContainerHighest = NoriColors.elevated,
    outline = NoriColors.border,
    outlineVariant = NoriColors.border,
    error = NoriColors.danger,
    onError = NoriColors.bg,
    scrim = Color(0xCC000000),
)

/**
 * Typografie mit deutlicher Abstufung.
 *
 * Material voreingestellt setzt Überschriften und Fließtext dicht
 * beieinander. In einer Liste aus Coverkacheln braucht der Titel dagegen
 * spürbar mehr Gewicht als die Zeile darunter, sonst verschwimmt beides.
 */
private val NoriTypography = Typography(
    displaySmall = TextStyle(fontSize = 30.sp, lineHeight = 36.sp, fontWeight = FontWeight.SemiBold),
    headlineMedium = TextStyle(fontSize = 24.sp, lineHeight = 30.sp, fontWeight = FontWeight.SemiBold),
    headlineSmall = TextStyle(fontSize = 20.sp, lineHeight = 26.sp, fontWeight = FontWeight.SemiBold),
    titleLarge = TextStyle(fontSize = 18.sp, lineHeight = 24.sp, fontWeight = FontWeight.SemiBold),
    titleMedium = TextStyle(fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.SemiBold),
    titleSmall = TextStyle(fontSize = 13.sp, lineHeight = 18.sp, fontWeight = FontWeight.SemiBold),
    bodyLarge = TextStyle(fontSize = 15.sp, lineHeight = 22.sp),
    bodyMedium = TextStyle(fontSize = 14.sp, lineHeight = 20.sp),
    bodySmall = TextStyle(fontSize = 12.sp, lineHeight = 17.sp),
    labelLarge = TextStyle(fontSize = 14.sp, lineHeight = 18.sp, fontWeight = FontWeight.SemiBold),
    labelMedium = TextStyle(fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.Medium),
    labelSmall = TextStyle(fontSize = 11.sp, lineHeight = 14.sp, fontWeight = FontWeight.Medium),
)

/** Runde Ecken wie auf Apple: 14 für Cover, 10 für kleine Kacheln. */
private val NoriShapes = Shapes(
    extraSmall = RoundedCornerShape(8.dp),
    small = RoundedCornerShape(10.dp),
    medium = RoundedCornerShape(14.dp),
    large = RoundedCornerShape(20.dp),
    extraLarge = RoundedCornerShape(28.dp),
)

@Composable
fun NoriTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = NoriScheme,
        typography = NoriTypography,
        shapes = NoriShapes,
        content = content,
    )
}
