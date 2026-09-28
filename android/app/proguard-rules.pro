# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.

# Play Core isn't included (no Play Store downloads); Flutter's engine
# references it only for deferred components, so silence R8 about it.
-dontwarn com.google.android.play.core.**

# Keep Flutter classes
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.**

# ML Kit (screenshot scanning) is disabled for the offline build.
# -keep class com.google.mlkit.** { *; }
# -keep class com.google.android.gms.** { *; }
# -dontwarn com.google.mlkit.**
# -dontwarn com.google.android.gms.**
# -keep class com.google.mlkit.vision.text.** { *; }


# Keep OpenCV Dart plugin classes
-keep class org.opencv.** { *; }
-dontwarn org.opencv.**

# Image/camera libraries (screenshot scanning, disabled)
# -keep class androidx.exifinterface.** { *; }
# -keep class androidx.camera.** { *; }

# Keep plugin classes
# -keep class com.kasem.receive_sharing_intent.** { *; }  # screenshot sharing (disabled)
-keep class io.flutter.plugins.** { *; }

# General Flutter plugin rules
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep NDK classes
-keep class androidx.annotation.** { *; }

# Keep serialization classes
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
}

# Suppress warnings for missing classes that are optional
-dontwarn javax.annotation.**
-dontwarn javax.inject.**
-dontwarn sun.misc.Unsafe

# Fix for receive_sharing_intent and shared_preferences path issues
# -dontwarn com.kasem.**  # screenshot sharing (disabled)
-dontwarn io.flutter.plugins.sharedpreferences.**
