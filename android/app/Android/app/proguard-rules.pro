-keeppackagenames **
-keep class skip.** { *; }
-keep class tools.skip.** { *; }
-keep class kotlin.jvm.functions.** {*;}
-keep class com.sun.jna.** { *; }
-dontwarn java.awt.**
-keep class * implements com.sun.jna.** { *; }
-keep class * implements skip.bridge.** { *; }
-keep class **._ModuleBundleAccessor_* { *; }

# The Kotlin classes Swift reaches by name through SkipBridge's reflection (the composers,
# AndroidDocuments, AndroidPlatform): nothing in Kotlin references them, so R8 would drop them.
-keep class piru.module.** { *; }
