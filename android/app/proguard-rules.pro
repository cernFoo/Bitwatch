# Keep BitWatch's own Kotlin classes referenced only via MethodChannel
# reflection-free calls; nothing special required, but keep the service and
# receiver classes fully so the manifest component names resolve at runtime.
-keep class com.bitwatch.app.** { *; }

# Flutter embedding
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Flutter's embedding references Google Play Core "deferred components"
# (dynamic feature delivery) classes for an optional code path BitWatch
# doesn't use and has no dependency on. Without these lines R8 fails the
# release build with "Missing class com.google.android.play.core.*" errors.
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
