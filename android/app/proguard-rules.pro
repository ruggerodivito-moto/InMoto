# kotlinx.serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class **$$serializer { *; }
-keepclasseswithmembers class com.divito.inmoto.** {
    *** Companion;
}
-keep,includedescriptorclasses class com.divito.inmoto.**$$serializer { *; }
