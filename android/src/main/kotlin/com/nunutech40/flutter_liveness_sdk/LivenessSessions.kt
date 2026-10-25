package com.nunutech40.flutter_liveness_sdk

/** Process-local rendezvous between a plugin engine and its native capture Activity. */
internal object LivenessSessions {
    private data class Session(
        val emit: (Map<String, Any?>) -> Unit,
        val complete: (Map<String, Any?>) -> Unit,
        var cancel: (() -> Unit)? = null,
        var cancellationRequested: Boolean = false,
    )

    private val sessions = mutableMapOf<String, Session>()

    @Synchronized
    fun register(id: String, emit: (Map<String, Any?>) -> Unit, complete: (Map<String, Any?>) -> Unit) {
        sessions[id] = Session(emit, complete)
    }

    @Synchronized
    fun has(id: String): Boolean = sessions.containsKey(id)

    @Synchronized
    fun attachCancel(id: String, cancel: () -> Unit) {
        val session = sessions[id] ?: return
        session.cancel = cancel
        if (session.cancellationRequested) cancel()
    }

    @Synchronized
    fun emit(id: String, event: Map<String, Any?>) { sessions[id]?.emit?.invoke(event) }

    @Synchronized
    fun cancel(id: String) {
        val session = sessions[id] ?: return
        session.cancellationRequested = true
        session.cancel?.invoke()
    }

    @Synchronized
    fun complete(
        id: String,
        status: String,
        errorCode: String? = null,
        selfiePath: String? = null,
        evidencePaths: Map<String, String> = emptyMap(),
    ) {
        val session = sessions.remove(id) ?: return
        session.complete(mapOf(
            "status" to status,
            "errorCode" to errorCode,
            "selfiePath" to selfiePath,
            "evidencePaths" to evidencePaths,
        ))
    }
}
