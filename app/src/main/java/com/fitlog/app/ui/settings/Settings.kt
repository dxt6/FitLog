package com.fitlog.app.ui.settings

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.ScaffoldDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.fitlog.app.backup.BackupManager
import com.fitlog.app.data.Graph
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

@Composable
fun SettingsScreen() {
    val context = LocalContext.current
    val repo = Graph.repository

    var threshold by remember { mutableStateOf(repo.getDefaultThreshold().toString()) }
    var reminderOn by remember { mutableStateOf(repo.isReminderEnabled()) }
    var useLb by remember { mutableStateOf(repo.getUnit() == "lb") }

    val scope = rememberCoroutineScope()

    val exportLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/json")
    ) { uri ->
        if (uri != null) {
            scope.launch(Dispatchers.IO) {
                val json = BackupManager.toJson(repo.exportData())
                context.contentResolver.openOutputStream(uri)?.use { it.write(json.toByteArray()) }
            }
        }
    }

    val importMerge = remember { mutableStateOf<Boolean?>(null) }
    val importLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri != null && importMerge.value != null) {
            scope.launch(Dispatchers.IO) {
                val json = context.contentResolver.openInputStream(uri)?.use { it.bufferedReader().readText() }
                if (!json.isNullOrBlank()) {
                    val data = BackupManager.fromJson(json)
                    repo.importData(data, importMerge.value!!)
                }
            }
        }
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { }

    val notifGranted = Build.VERSION.SDK_INT < 33 ||
        ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
        android.content.pm.PackageManager.PERMISSION_GRANTED

    Scaffold(
        contentWindowInsets = ScaffoldDefaults.contentWindowInsets.only(WindowInsetsSides.Horizontal + WindowInsetsSides.Bottom),
        topBar = { TopAppBar(title = { Text("设置") }) }
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("动作间隔提醒", style = MaterialTheme.typography.titleMedium)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("开启提醒", modifier = Modifier.weight(1f))
                        Switch(checked = reminderOn, onCheckedChange = {
                            reminderOn = it
                            repo.setReminderEnabled(it)
                        })
                    }
                    OutlinedTextField(
                        value = threshold,
                        onValueChange = {
                            threshold = it.filter { c -> c.isDigit() }
                            it.toIntOrNull()?.let { h -> repo.setDefaultThreshold(h) }
                        },
                        label = { Text("默认间隔阈值（小时）") },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                    Text("超过该时长未练某个动作，会发通知提醒。每个动作也可单独设置。", style = MaterialTheme.typography.bodySmall)

                    if (Build.VERSION.SDK_INT >= 33 && !notifGranted) {
                        Spacer(Modifier.height(4.dp))
                        Button(onClick = { permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS) }) {
                            Text("开启通知权限")
                        }
                    }
                }
            }

            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("单位", style = MaterialTheme.typography.titleMedium)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("使用磅(lb)显示（数据仍以 kg 存储）", modifier = Modifier.weight(1f))
                        Switch(checked = useLb, onCheckedChange = {
                            useLb = it
                            repo.setUnit(if (it) "lb" else "kg")
                        })
                    }
                }
            }

            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("数据备份", style = MaterialTheme.typography.titleMedium)
                    Button(onClick = { exportLauncher.launch("fitlog_backup.json") }, modifier = Modifier.fillMaxWidth()) {
                        Text("导出为 JSON 文件")
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = {
                            importMerge.value = true
                            importLauncher.launch(arrayOf("*/*"))
                        }, modifier = Modifier.weight(1f)) { Text("导入（合并）") }
                        Button(onClick = {
                            importMerge.value = false
                            importLauncher.launch(arrayOf("*/*"))
                        }, modifier = Modifier.weight(1f)) { Text("导入（覆盖）") }
                    }
                    Text("合并：保留现有数据并加入备份中的记录；覆盖：先清空再写入。", style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }
}
