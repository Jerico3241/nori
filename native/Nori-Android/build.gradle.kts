// Wurzelprojekt. Die Plugins werden hier nur deklariert und im Modul
// angewandt — so steht die Version genau einmal im Katalog.
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.kotlin.serialization) apply false
}
