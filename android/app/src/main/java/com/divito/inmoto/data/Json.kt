package com.divito.inmoto.data

import kotlinx.serialization.json.Json

/** Istanza JSON condivisa: tollerante ai campi extra/mancanti come iOS. */
val AppJson: Json = Json {
    ignoreUnknownKeys = true
    encodeDefaults = true
    isLenient = true
}
