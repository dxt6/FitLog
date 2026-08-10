package com.fitlog.app.ui.stats

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewModelScope
import com.fitlog.app.data.Graph
import com.fitlog.app.data.model.Exercise
import com.fitlog.app.data.model.SetWithDate
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class StatsViewModel : ViewModel() {
    private val repo = Graph.repository
    val exercises: StateFlow<List<Exercise>> = repo.observeExercises()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    fun observeSets(exerciseId: String): StateFlow<List<SetWithDate>> =
        repo.observeSetsWithDate(exerciseId)
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())
}

data class StatsResult(
    val maxWeight: Float?,
    val maxReps: Int?,
    val estOneRm: Float?,
    val totalVolume: Float,
    val volumeByDate: List<Pair<String, Float>>,
    val weightByDate: List<Pair<String, Float>>,
    val rpeByDate: List<Pair<String, Float>>
)

fun computeStats(sets: List<SetWithDate>): StatsResult {
    if (sets.isEmpty()) {
        return StatsResult(null, null, null, 0f, emptyList(), emptyList(), emptyList())
    }
    val maxWeight = sets.maxOfOrNull { it.set.weight }
    val maxReps = sets.maxOfOrNull { it.set.reps }
    val estOneRm = sets.maxOfOrNull { it.set.weight * (1f + it.set.reps / 30f) }

    val byDate = sets.groupBy { it.sessionDate }
    val volumeByDate = byDate.mapValues { (_, v) -> v.sumOf { (it.set.weight * it.set.reps).toDouble() }.toFloat() }
    val weightByDate = byDate.mapValues { (_, v) -> v.maxOf { it.set.weight } }
    val rpeByDate = byDate.mapValues { (_, v) ->
        val rs = v.mapNotNull { it.set.rpe }
        if (rs.isEmpty()) 0f else rs.average().toFloat()
    }

    val totalVolume = volumeByDate.values.sumOf { it.toDouble() }.toFloat()

    val sortedDates = byDate.keys.sorted()
    fun ordered(map: Map<String, Float>) = sortedDates.map { it to (map[it] ?: 0f) }

    return StatsResult(
        maxWeight = maxWeight,
        maxReps = maxReps,
        estOneRm = estOneRm,
        totalVolume = totalVolume,
        volumeByDate = ordered(volumeByDate),
        weightByDate = ordered(weightByDate),
        rpeByDate = ordered(rpeByDate).filter { it.second > 0f }
    )
}

@Composable
fun StatsScreen() {
    val vm: StatsViewModel = viewModel()
    val exercises by vm.exercises.collectAsState()

    var selectedId by remember { mutableStateOf<String?>(null) }
    var expanded by remember { mutableStateOf(false) }

    LaunchedEffect(exercises) {
        if (selectedId == null && exercises.isNotEmpty()) {
            selectedId = exercises.first().id
        }
    }

    val sets by if (selectedId != null) vm.observeSets(selectedId!!).collectAsState() else remember { mutableStateOf<List<SetWithDate>>(emptyList()) }
    val stats = remember(sets) { computeStats(sets) }
    val selectedExercise = exercises.firstOrNull { it.id == selectedId }

    Scaffold(
        topBar = { TopAppBar(title = { Text("统计") }) }
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).padding(horizontal = 12.dp, vertical = 8.dp)
        ) {
            Box {
                Button(onClick = { expanded = true }) {
                    Text(selectedExercise?.name ?: "选择动作")
                }
                DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                    exercises.forEach { ex ->
                        DropdownMenuItem(
                            text = { Text(ex.name) },
                            onClick = { selectedId = ex.id; expanded = false }
                        )
                    }
                }
            }

            Spacer(Modifier.height(12.dp))

            if (sets.isEmpty()) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text("该动作还没有训练记录，先去『训练』页记录吧。", style = MaterialTheme.typography.bodyLarge)
                }
            } else {
                LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    item {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            StatCard("最大重量", stats.maxWeight?.let { "${fmt(it)}kg" } ?: "-", Modifier.weight(1f))
                            StatCard("最大次数", stats.maxReps?.toString() ?: "-", Modifier.weight(1f))
                        }
                    }
                    item {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            StatCard("估算 1RM", stats.estOneRm?.let { "${fmt(it)}kg" } ?: "-", Modifier.weight(1f))
                            StatCard("总容量", "${fmt(stats.totalVolume)}kg", Modifier.weight(1f))
                        }
                    }
                    item { ChartCard("重量趋势（每次最大重量）", stats.weightByDate.map { it.second }, isBar = false) }
                    item { ChartCard("训练容量（每次）", stats.volumeByDate.map { it.second }, isBar = true) }
                    if (stats.rpeByDate.isNotEmpty()) {
                        item { ChartCard("RPE 趋势（平均）", stats.rpeByDate.map { it.second }, isBar = false) }
                    }
                }
            }
        }
    }
}

@Composable
private fun StatCard(title: String, value: String, modifier: Modifier = Modifier) {
    Card(modifier = modifier) {
        Column(modifier = Modifier.padding(12.dp)) {
            Text(title, style = MaterialTheme.typography.labelMedium)
            Spacer(Modifier.height(4.dp))
            Text(value, style = MaterialTheme.typography.titleLarge)
        }
    }
}

@Composable
private fun ChartCard(title: String, values: List<Float>, isBar: Boolean) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(12.dp)) {
            Text(title, style = MaterialTheme.typography.labelMedium)
            Spacer(Modifier.height(8.dp))
            if (values.isEmpty()) {
                Text("暂无数据", style = MaterialTheme.typography.bodySmall)
            } else {
                Box(
                    modifier = Modifier.fillMaxWidth().height(140.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(MaterialTheme.colorScheme.surfaceVariant)
                        .padding(8.dp)
                ) {
                    if (isBar) BarChart(values) else LineChart(values)
                }
            }
        }
    }
}

fun fmt(v: Float): String = if (v % 1 == 0f) v.toInt().toString() else String.format("%.1f", v)

@Composable
private fun LineChart(values: List<Float>) {
    val color = MaterialTheme.colorScheme.primary
    Canvas(modifier = Modifier.fillMaxSize()) {
        if (values.isEmpty()) return@Canvas
        val max = (values.maxOrNull() ?: 1f).coerceAtLeast(0.0001f)
        val pad = size.height * 0.12f
        val usableH = size.height - 2 * pad
        val stepX = if (values.size > 1) (size.width - 2 * pad) / (values.size - 1) else 0f
        val path = Path()
        values.forEachIndexed { i, v ->
            val x = pad + i * stepX
            val y = size.height - pad - (v / max) * usableH
            if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }
        drawPath(path, color, style = Stroke(width = 3f))
        values.forEachIndexed { i, v ->
            val x = pad + i * stepX
            val y = size.height - pad - (v / max) * usableH
            drawCircle(color, radius = 3f, center = androidx.compose.ui.geometry.Offset(x, y))
        }
    }
}

@Composable
private fun BarChart(values: List<Float>) {
    val color = MaterialTheme.colorScheme.secondary
    Canvas(modifier = Modifier.fillMaxSize()) {
        if (values.isEmpty()) return@Canvas
        val max = (values.maxOrNull() ?: 1f).coerceAtLeast(0.0001f)
        val pad = size.height * 0.12f
        val usableH = size.height - 2 * pad
        val slot = size.width / values.size
        val barW = slot * 0.6f
        values.forEachIndexed { i, v ->
            val h = (v / max) * usableH
            val x = i * slot + (slot - barW) / 2
            val y = size.height - pad - h
            drawRect(color, topLeft = androidx.compose.ui.geometry.Offset(x, y), size = androidx.compose.ui.geometry.Size(barW, h))
        }
    }
}
