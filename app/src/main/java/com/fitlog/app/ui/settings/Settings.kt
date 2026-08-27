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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
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
import com.fitlog.app.data.AppConfig
import com.fitlog.app.data.Graph
import com.fitlog.app.data.model.VoiceDraft
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import android.widget.Toast
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.text.style.TextOverflow
import java.text.SimpleDateFormat
import java.util.Locale

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
                    Text("硅基流动 API Key", style = MaterialTheme.typography.titleMedium)
                    var apiKey by remember { mutableStateOf(repo.getApiKey()) }
                    OutlinedTextField(
                        value = apiKey,
                        onValueChange = { apiKey = it },
                        label = { Text("sk- 开头密钥（ASR 与 LLM 共用）") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = {
                            repo.setApiKey(apiKey)
                            Toast.makeText(context, "已保存 API Key", Toast.LENGTH_SHORT).show()
                        }, modifier = Modifier.weight(1f)) { Text("保存") }
                        OutlinedButton(onClick = {
                            apiKey = AppConfig.DEFAULT_API_KEY
                            repo.setApiKey(apiKey)
                            Toast.makeText(context, "已恢复默认 Key", Toast.LENGTH_SHORT).show()
                        }, modifier = Modifier.weight(1f)) { Text("恢复默认") }
                    }
                    Text(
                        "语音录入的「语音转写」与「结构化解析」都走硅基流动同一个 Key；可在 siliconflow.cn 后台「API 密钥」复制 sk- 开头密钥覆盖。",
                        style = MaterialTheme.typography.bodySmall
                    )
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

            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("语音草稿（解析失败留存）", style = MaterialTheme.typography.titleMedium)
                    val drafts by repo.observeDrafts().collectAsState(initial = emptyList())
                    if (drafts.isEmpty()) {
                        Text("暂无草稿", style = MaterialTheme.typography.bodySmall)
                    } else {
                        LazyColumn(modifier = Modifier.fillMaxWidth().heightIn(max = 220.dp)) {
                            items(drafts, key = { it.id }) { d: VoiceDraft ->
                                Row(
                                    modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(
                                            d.rawText,
                                            style = MaterialTheme.typography.bodyMedium,
                                            maxLines = 2,
                                            overflow = TextOverflow.Ellipsis
                                        )
                                        Text(
                                            SimpleDateFormat("MM-dd HH:mm", Locale.CHINA).format(java.util.Date(d.createdAt)),
                                            style = MaterialTheme.typography.labelSmall
                                        )
                                    }
                                    IconButton(onClick = {
                                        scope.launch(Dispatchers.IO) { repo.deleteDraft(d) }
                                    }) {
                                        Icon(Icons.Filled.Delete, contentDescription = "删除草稿", tint = MaterialTheme.colorScheme.error)
                                    }
                                }
                                HorizontalDivider()
                            }
                        }
                        Text("语音没解析出来时，听到的原话会留在这里，方便你手动补录。", style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }
    }
}
