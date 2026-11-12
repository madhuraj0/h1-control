plugins {
    kotlin("multiplatform")
}

kotlin {
    jvmToolchain(17)
    jvm()

    // Static framework consumed by the macOS menu bar app (macApp/).
    macosArm64 {
        binaries.framework {
            baseName = "H1Core"
            isStatic = true
        }
    }

    sourceSets {
        commonTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}

