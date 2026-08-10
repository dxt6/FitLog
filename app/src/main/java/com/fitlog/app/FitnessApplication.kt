package com.fitlog.app

import android.app.Application
import com.fitlog.app.data.Graph
import com.fitlog.app.reminder.ReminderScheduler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class FitnessApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        Graph.init(this)
        CoroutineScope(Dispatchers.IO).launch {
            Graph.repository.seedIfEmpty()
        }
        ReminderScheduler.schedule(this)
    }
}
