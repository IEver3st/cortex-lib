/**
 * Everest Lib - React UI System
 * Notifications + Progress Bars
 */

const { useState, useEffect, useCallback, useRef } = React;

// ============================================================================
// WEATHER ZONE EDITOR APP
// ============================================================================

const WEATHER_EDITOR_APP_ID = 'weatherzonesEditor';
const WEATHER_EDITOR_MAP_URL = 'https://cfx-nui-es_weatherzones/assets/atlasmap.png';
const WEATHER_EDITOR_MAP_SIZE = 2048;

const WEATHER_DEFAULT_BOUNDS = {
    minX: -4700,
    maxX: 4600,
    minY: -4870,
    maxY: 8600
};

function WeatherZoneEditorApp({ appState, setUiApps }) {
    const open = appState && appState.open;
    const payload = appState && appState.payload ? appState.payload : {};

    const [zones, setZones] = useState([]);
    const [selectedId, setSelectedId] = useState(null);
    const [view, setView] = useState({ x: 0, y: 0, scale: 1 });
    const [status, setStatus] = useState(null);
    const [drawMode, setDrawMode] = useState(false);

    const minScaleRef = useRef(1);
    const openedRef = useRef(false);

    const editorMapSize = payload.mapSize || WEATHER_EDITOR_MAP_SIZE;
    const [calibration, setCalibration] = useState({
        active: false,
        stage: 'idle',
        anchor: null,
        point: null
    });

    const lastPayloadRef = useRef(null);

    useEffect(() => {
        if (!open) {
            openedRef.current = false;
            return;
        }

        if (payload && payload.zones && payload !== lastPayloadRef.current) {
            const incoming = Array.isArray(payload.zones) ? payload.zones : [];
            setZones(incoming.map(normalizeZone));
            setSelectedId(incoming[0] && incoming[0].id || null);
            lastPayloadRef.current = payload;
        }

        if (payload && payload.mapSize && open) {
            const scale = Math.max(0.1, WEATHER_EDITOR_MAP_SIZE / payload.mapSize);
            minScaleRef.current = scale;
            setView(prev => ({ ...prev, scale: Math.max(prev.scale, scale) }));
        }

        if (!openedRef.current) {
            openedRef.current = true;
            setView(prev => ({ ...prev, scale: Math.max(prev.scale, minScaleRef.current || 1) }));
        }
    }, [open, payload]);

    const closeEditor = useCallback(() => {
        setUiApps(prev => ({
            ...prev,
            [WEATHER_EDITOR_APP_ID]: { ...(prev[WEATHER_EDITOR_APP_ID] || {}), open: false }
        }));

        fetch(`https://${GetParentResourceName()}/cortex:uiEvent`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify({ appId: WEATHER_EDITOR_APP_ID, type: 'close' })
        }).catch(() => { });
    }, [setUiApps]);

    const sendEvent = useCallback(async (type, eventPayload) => {
        try {
            const res = await fetch(`https://${GetParentResourceName()}/cortex:uiEvent`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify({ appId: WEATHER_EDITOR_APP_ID, type, payload: eventPayload || {} })
            });
            return await res.json().catch(() => ({}));
        } catch (e) {
            return { ok: false, error: 'network' };
        }
    }, []);

    const selectZone = useCallback((zoneId) => {
        setSelectedId(zoneId);
        // Disable draw mode when switching zones to prevent accidents
        setDrawMode(false);
    }, []);

    const addPointToZone = useCallback((zoneId, point) => {
        setZones(prev => prev.map(zone => {
            if (zone.id !== zoneId) return zone;
            return { ...zone, points: [...zone.points, point] };
        }));
    }, []);

    const removePointFromZone = useCallback((zoneId, index) => {
        setZones(prev => prev.map(zone => {
            if (zone.id !== zoneId) return zone;
            return { ...zone, points: zone.points.filter((_, idx) => idx !== index) };
        }));
    }, []);

    const undoLastPoint = useCallback((zoneId) => {
        setZones(prev => prev.map(zone => {
            if (zone.id !== zoneId) return zone;
            if (zone.points.length === 0) return zone;
            return { ...zone, points: zone.points.slice(0, -1) };
        }));
    }, []);

    const clearPoints = useCallback((zoneId) => {
        setZones(prev => prev.map(zone => {
            if (zone.id !== zoneId) return zone;
            return { ...zone, points: [] };
        }));
    }, []);

    const updateZone = useCallback((zoneId, patch) => {
        setZones(prev => prev.map(zone => {
            if (zone.id !== zoneId) return zone;
            return { ...zone, ...patch };
        }));
    }, []);

    // Declare bounds and mapSize BEFORE they are used in addZone callback
    const bounds = payload.bounds || WEATHER_DEFAULT_BOUNDS;
    const mapSize = payload.mapSize || WEATHER_EDITOR_MAP_SIZE;

    const centerOnZone = useCallback((zone) => {
        if (!zone || !zone.points || zone.points.length === 0) return;

        // Calculate centroid of zone points
        let sumX = 0, sumY = 0;
        for (const pt of zone.points) {
            sumX += pt.x;
            sumY += pt.y;
        }
        const centroidX = sumX / zone.points.length;
        const centroidY = sumY / zone.points.length;

        // Convert world coords to map coords
        const mapX = ((centroidX - bounds.minX) / (bounds.maxX - bounds.minX)) * mapSize;
        const mapY = (1 - (centroidY - bounds.minY) / (bounds.maxY - bounds.minY)) * mapSize;

        // Calculate zone size to determine zoom
        let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
        for (const pt of zone.points) {
            if (pt.x < minX) minX = pt.x;
            if (pt.x > maxX) maxX = pt.x;
            if (pt.y < minY) minY = pt.y;
            if (pt.y > maxY) maxY = pt.y;
        }
        const zoneWidth = ((maxX - minX) / (bounds.maxX - bounds.minX)) * mapSize;
        const zoneHeight = ((maxY - minY) / (bounds.maxY - bounds.minY)) * mapSize;
        const zoneDim = Math.max(zoneWidth, zoneHeight, 100);

        // Set scale to fit zone with some padding (aim for zone to be ~40% of viewport)
        const viewportSize = Math.min(window.innerWidth - 320, window.innerHeight - 48);
        const targetScale = Math.min(2.5, Math.max(0.5, (viewportSize * 0.4) / zoneDim));

        // Center the view
        const viewportCenterX = (window.innerWidth - 320) / 2;
        const viewportCenterY = (window.innerHeight - 48) / 2;

        setView({
            x: viewportCenterX - (mapX * targetScale),
            y: viewportCenterY - (mapY * targetScale),
            scale: targetScale
        });
    }, [bounds, mapSize]);

    const addZone = useCallback(() => {
        const center = {
            x: (bounds.minX + bounds.maxX) / 2,
            y: (bounds.minY + bounds.maxY) / 2
        };
        const size = (bounds.maxX - bounds.minX) * 0.02;
        const newZone = {
            id: `zone_${Date.now()}`,
            label: 'New Zone',
            mode: 'dynamic',
            weather: 'CLEAR',
            weathers: ['CLEAR', 'CLOUDS'],
            intervalMinutes: 10,
            thickness: 200,
            points: [
                { x: center.x - size, y: center.y - size, z: 0 },
                { x: center.x + size, y: center.y - size, z: 0 },
                { x: center.x + size, y: center.y + size, z: 0 },
                { x: center.x - size, y: center.y + size, z: 0 }
            ]
        };

        setZones(prev => [...prev, newZone]);
        setSelectedId(newZone.id);
        setDrawMode(true);
        // Defer centering slightly to ensure state update has processed/zone exists in context if needed
        // But since we pass the object directly, it should be fine.
        setTimeout(() => centerOnZone(newZone), 50);
    }, [bounds, centerOnZone]);

    const removeZone = useCallback((zoneId) => {
        setZones(prev => prev.filter(zone => zone.id !== zoneId));
        setSelectedId(prev => (prev === zoneId ? null : prev));
        if (selectedId === zoneId) setDrawMode(false);
    }, [selectedId]);

    const saveZones = useCallback(async () => {
        setStatus('Saving...');
        const res = await sendEvent('save', { zones });
        if (res && res.ok) {
            setStatus('Saved');
            setTimeout(() => setStatus(null), 1200);
        } else {
            setStatus('Save failed');
            setTimeout(() => setStatus(null), 2000);
        }
    }, [sendEvent, zones]);

    const zoomIn = useCallback(() => {
        setView(prev => ({ ...prev, scale: Math.min(3, prev.scale + 0.2) }));
    }, []);

    const zoomOut = useCallback(() => {
        const minScale = minScaleRef.current || 0.1;
        setView(prev => ({ ...prev, scale: Math.max(minScale, prev.scale - 0.2) }));
    }, []);

    const startCalibration = useCallback(() => {
        setCalibration({ active: true, stage: 'pickAnchor', anchor: null, point: null });
        setStatus('Calibration active - follow instructions on map');
    }, []);

    const setCalibrationAnchor = useCallback(async (anchorPayload) => {
        setCalibration({
            active: true,
            stage: 'pickPoint',
            anchor: { map: anchorPayload, world: null },
            point: null
        });
        setStatus('Anchor A placed - now place anchor B');

        const res = await sendEvent('getPlayerCoords', {});
        if (!res || !res.ok || !res.coords) {
            const reason = res && res.error ? res.error : 'no_coords';
            setStatus(`Calibration failed: ${reason}`);
            setTimeout(() => setStatus(null), 2500);
            setCalibration({ active: false, stage: 'idle', anchor: null, point: null });
            return;
        }

        setCalibration(prev => ({
            ...prev,
            anchor: { map: anchorPayload, world: res.coords }
        }));
    }, [sendEvent]);

    const finishCalibration = useCallback(async (pointPayload) => {
        if (!calibration.anchor) return;

        setCalibration(prev => ({
            ...prev,
            point: { map: pointPayload, world: null }
        }));

        const res = await sendEvent('getPlayerCoords', {});
        if (!res || !res.ok || !res.coords) {
            const reason = res && res.error ? res.error : 'no_coords';
            setStatus(`Calibration failed: ${reason}`);
            setTimeout(() => setStatus(null), 2500);
            setCalibration({ active: false, stage: 'idle', anchor: null, point: null });
            return;
        }

        const boundsRes = await sendEvent('saveBounds', {
            map: {
                a: calibration.anchor.map,
                b: pointPayload
            },
            world: {
                a: calibration.anchor.world || res.coords,
                b: res.coords
            },
            mapSize: editorMapSize
        });

        if (boundsRes && boundsRes.ok) {
            setStatus('Calibration saved');
            setTimeout(() => setStatus(null), 1500);
        } else {
            const reason = boundsRes && boundsRes.error ? boundsRes.error : 'invalid_bounds';
            setStatus(`Calibration failed: ${reason}`);
            setTimeout(() => setStatus(null), 2500);
        }

        setCalibration({ active: false, stage: 'idle', anchor: null, point: null });
    }, [calibration.anchor, sendEvent]);


    const autoCalibrate = useCallback(async () => {
        setStatus('Auto-calibrating...');
        const res = await sendEvent('autoCalibrate', {});
        if (res && res.ok) {
            setStatus('Calibration complete');
            setTimeout(() => setStatus(null), 1500);
        } else {
            const reason = res && res.error ? res.error : 'unknown';
            setStatus(`Calibration failed: ${reason}`);
            setTimeout(() => setStatus(null), 2500);
        }
    }, [sendEvent]);


    useEffect(() => {
        if (!open) return;
        const onKeyDown = (event) => {
            if (event.key === 'Escape') {
                if (calibration.active) {
                    setCalibration({ active: false, stage: 'idle', anchor: null, point: null });
                    setStatus(null);
                    return;
                }
                if (drawMode) {
                    setDrawMode(false);
                    return;
                }
                closeEditor();
            }
        };
        window.addEventListener('keydown', onKeyDown);
        return () => window.removeEventListener('keydown', onKeyDown);
    }, [open, closeEditor, calibration.active, drawMode]);

    if (!open) return null;

    return React.createElement('div', { className: 'es-editor-root' },
        React.createElement(EditorToolbar, { onSave: saveZones, onClose: closeEditor, onCalibrate: autoCalibrate, onZoomIn: zoomIn, onZoomOut: zoomOut, status }),
        React.createElement('div', { className: 'es-editor-workspace' },
            React.createElement(EditorSidebar, {
                zones,
                selectedId,
                onSelect: selectZone,
                onUpdate: updateZone,
                onDelete: removeZone,
                onCenter: centerOnZone,
                onAdd: addZone,
                drawMode,
                setDrawMode,
                onUndo: undoLastPoint,
                onClearPoints: clearPoints,
                bounds,
                mapSize,
                view
            }),
            React.createElement(EditorMap, {
                zones,
                selectedId,
                onSelect: selectZone,
                onUpdate: updateZone,
                onAddPoint: addPointToZone,
                onRemovePoint: removePointFromZone,
                onCalibrateAnchor: setCalibrationAnchor,
                onCalibratePoint: finishCalibration,
                calibration,
                onCancelCalibration: () => {
                    setCalibration({ active: false, stage: 'idle', anchor: null, point: null });
                    setStatus(null);
                },
                view,
                setView,
                minScaleRef,
                bounds: payload.bounds || WEATHER_DEFAULT_BOUNDS,
                mapUrl: payload.mapUrl,
                mapSize: payload.mapSize || WEATHER_EDITOR_MAP_SIZE,
                drawMode
            })

        )
    );
}

function normalizeZone(zone) {
    if (!zone) return zone;
    const points = Array.isArray(zone.points) ? zone.points.map((point) => ({
        x: typeof point.x === 'number' ? point.x : point[0],
        y: typeof point.y === 'number' ? point.y : point[1],
        z: typeof point.z === 'number' ? point.z : point[2]
    })) : [];

    return {
        id: zone.id,
        label: zone.label || zone.id || 'Zone',
        mode: zone.mode || 'dynamic',
        weather: zone.weather || 'CLEAR',
        weathers: Array.isArray(zone.weathers) ? zone.weathers : (zone.weather ? [zone.weather] : []),
        intervalMinutes: zone.intervalMinutes || 10,
        thickness: zone.thickness || 200,
        points
    };
}

function EditorToolbar({ onSave, onClose, onCalibrate, onZoomIn, onZoomOut, status }) {
    return React.createElement('div', { className: 'es-editor-toolbar' },
        React.createElement('div', { className: 'es-editor-title' },
            React.createElement('span', { style: { color: 'var(--es-warning)' } }, 'ES'),
            ' WEATHER'
        ),
        React.createElement('div', { className: 'es-editor-spacer' }),
        status ? React.createElement('div', { className: 'es-editor-status' }, status) : null,
        React.createElement('div', { className: 'es-editor-actions' },
            React.createElement('button', { className: 'es-editor-btn calibrate', onClick: onCalibrate }, 'Auto-Calibrate'),
            React.createElement('button', { className: 'es-editor-btn primary', onClick: onSave }, 'Save Changes'),
            React.createElement('div', { className: 'es-toolbar-divider' }),
            React.createElement('div', { className: 'es-editor-zoom-controls' },
                React.createElement('button', { className: 'es-editor-btn icon', onClick: onZoomOut, title: 'Zoom Out' }, '−'),
                React.createElement('button', { className: 'es-editor-btn icon', onClick: onZoomIn, title: 'Zoom In' }, '+')
            ),
            React.createElement('button', { className: 'es-editor-btn ghost icon', onClick: onClose }, '✕')
        )
    );
}

function EditorSidebar({ zones, selectedId, onSelect, onUpdate, onDelete, onCenter, onAdd, drawMode, setDrawMode, onUndo, onClearPoints, bounds, mapSize, view }) {
    const selected = zones.find(zone => zone.id === selectedId);
    const [tab, setTab] = useState('config'); // 'config' | 'points' | 'debug'

    // Reset tab when selection changes
    useEffect(() => {
        setTab('config');
    }, [selectedId]);

    return React.createElement('div', { className: 'es-editor-sidebar' },
        React.createElement('div', { className: 'es-sidebar-header' },
            React.createElement('div', { className: 'es-sidebar-title' }, 'ZONES'),
            React.createElement('button', { className: 'es-editor-btn full-width primary', onClick: onAdd }, '+ NEW ZONE')
        ),
        React.createElement('div', { className: 'es-zone-list' },
            zones.map(zone => React.createElement('div', {
                key: zone.id,
                className: `es-zone-item${zone.id === selectedId ? ' active' : ''}`,
                onClick: () => onSelect(zone.id)
            },
                React.createElement('div', { className: 'es-zone-info' },
                    React.createElement('span', { className: 'es-zone-name' }, zone.label || zone.id),
                    React.createElement('span', { className: 'es-zone-meta' }, zone.mode === 'fixed' ? zone.weather : `${zone.weathers.length} weathers`)
                ),
                React.createElement('button', {
                    className: 'es-zone-delete',
                    onClick: (e) => {
                        e.stopPropagation();
                        // eslint-disable-next-line no-restricted-globals
                        if (confirm('Delete zone?')) onDelete(zone.id);
                    }
                }, '×')
            ))
        ),
        selected ? React.createElement('div', { className: 'es-selected-panel' },
            React.createElement('div', { className: 'es-panel-header' },
                React.createElement('div', { className: 'es-panel-title' }, selected.label || 'Unnamed Zone'),
                React.createElement('button', { className: 'es-icon-btn', onClick: () => onCenter && onCenter(selected), title: 'Center Map' }, '⌖')
            ),
            React.createElement('div', { className: 'es-draw-actions' },
                React.createElement('button', {
                    className: `es-editor-btn small ${drawMode ? 'primary' : ''}`,
                    onClick: () => setDrawMode(!drawMode),
                    title: 'Toggle Draw Mode'
                }, drawMode ? 'FINISH DRAWING' : 'DRAW POINTS'),
                drawMode && React.createElement(React.Fragment, null,
                    React.createElement('button', {
                        className: 'es-editor-btn small ghost',
                        onClick: () => onUndo(selected.id),
                        disabled: selected.points.length === 0,
                        title: 'Undo last point'
                    }, 'UNDO'),
                    React.createElement('button', {
                        className: 'es-editor-btn small ghost',
                        onClick: () => onClearPoints(selected.id),
                        disabled: selected.points.length === 0,
                        title: 'Clear all points'
                    }, 'CLEAR')
                )
            ),
            React.createElement('div', { className: 'es-panel-tabs' },
                React.createElement('button', { className: `es-tab ${tab === 'config' ? 'active' : ''}`, onClick: () => setTab('config') }, 'CONFIG'),
                React.createElement('button', { className: `es-tab ${tab === 'points' ? 'active' : ''}`, onClick: () => setTab('points') }, 'POINTS'),
                React.createElement('button', { className: `es-tab ${tab === 'debug' ? 'active' : ''}`, onClick: () => setTab('debug') }, 'DEBUG')
            ),
            React.createElement('div', { className: 'es-panel-content' },
                tab === 'config'
                    ? React.createElement(ZoneConfigForm, { selected, onUpdate })
                    : tab === 'points'
                        ? React.createElement(ZonePointsList, { selected })
                        : React.createElement(ZoneDebugView, { selected, bounds, mapSize, view })
            )
        ) : React.createElement('div', { className: 'es-empty-state' },
            React.createElement('span', null, 'Select a zone to edit'),
            React.createElement(EditorHelp, null)
        )
    );
}

function ZoneDebugView({ selected, bounds, mapSize, view }) {
    if (!selected) return null;

    const toMapCoords = (point) => {
        if (!bounds || !mapSize) return { x: 0, y: 0 };
        return {
            x: ((point.x - bounds.minX) / (bounds.maxX - bounds.minX)) * mapSize,
            y: (1 - (point.y - bounds.minY) / (bounds.maxY - bounds.minY)) * mapSize
        };
    };

    const modeText = String(selected.mode || 'unknown');
    const weatherText = modeText === 'fixed'
        ? String(selected.weather || '')
        : (Array.isArray(selected.weathers) ? selected.weathers.join(', ') : '');

    return React.createElement('div', { className: 'es-debug-view' },
        React.createElement('div', { className: 'es-debug-section' },
            React.createElement('div', { className: 'es-debug-section-title' }, 'ZONE'),
            React.createElement('div', { className: 'es-debug-grid' },
                React.createElement('span', { className: 'es-debug-key' }, 'ID:'),
                React.createElement('span', { className: 'es-debug-val' }, selected.id),
                React.createElement('span', { className: 'es-debug-key' }, 'Label:'),
                React.createElement('span', { className: 'es-debug-val' }, selected.label),
                React.createElement('span', { className: 'es-debug-key' }, 'Mode:'),
                React.createElement('span', { className: 'es-debug-val' }, modeText),
                React.createElement('span', { className: 'es-debug-key' }, modeText === 'fixed' ? 'Weather:' : 'Weathers:'),
                React.createElement('span', { className: 'es-debug-val' }, weatherText),
                modeText === 'dynamic' ? React.createElement(React.Fragment, null,
                    React.createElement('span', { className: 'es-debug-key' }, 'Interval:'),
                    React.createElement('span', { className: 'es-debug-val' }, `${Number(selected.intervalMinutes || 0)}m`)
                ) : null,
                React.createElement('span', { className: 'es-debug-key' }, 'Thickness:'),
                React.createElement('span', { className: 'es-debug-val' }, String(selected.thickness || 0)),
                React.createElement('span', { className: 'es-debug-key' }, 'Points:'),
                React.createElement('span', { className: 'es-debug-val' }, String(selected.points.length))
            )
        ),
        React.createElement('div', { className: 'es-debug-section' },
            React.createElement('div', { className: 'es-debug-section-title' }, 'MAP / VIEW'),
            React.createElement('div', { className: 'es-debug-grid' },
                React.createElement('span', { className: 'es-debug-key' }, 'Bounds X:'),
                React.createElement('span', { className: 'es-debug-val' }, bounds ? `${bounds.minX.toFixed(0)}..${bounds.maxX.toFixed(0)}` : 'n/a'),
                React.createElement('span', { className: 'es-debug-key' }, 'Bounds Y:'),
                React.createElement('span', { className: 'es-debug-val' }, bounds ? `${bounds.minY.toFixed(0)}..${bounds.maxY.toFixed(0)}` : 'n/a'),
                React.createElement('span', { className: 'es-debug-key' }, 'MapSize:'),
                React.createElement('span', { className: 'es-debug-val' }, String(mapSize)),
                React.createElement('span', { className: 'es-debug-key' }, 'Zoom:'),
                React.createElement('span', { className: 'es-debug-val' }, view.scale.toFixed(2)),
                React.createElement('span', { className: 'es-debug-key' }, 'Pan:'),
                React.createElement('span', { className: 'es-debug-val' }, `${view.x.toFixed(0)}, ${view.y.toFixed(0)}`)
            )
        ),
        React.createElement('div', { className: 'es-point-table-container' },
            React.createElement('table', { className: 'es-point-table' },
                React.createElement('thead', null,
                    React.createElement('tr', null,
                        React.createElement('th', null, '#'),
                        React.createElement('th', null, 'WX'),
                        React.createElement('th', null, 'WY'),
                        React.createElement('th', null, 'WZ'),
                        React.createElement('th', null, 'MX'),
                        React.createElement('th', null, 'MY')
                    )
                ),
                React.createElement('tbody', null,
                    selected.points.map((pt, i) => {
                        const mapPt = toMapCoords(pt);
                        const wz = typeof pt.z === 'number' ? pt.z : 0;
                        return React.createElement('tr', { key: i },
                            React.createElement('td', null, i + 1),
                            React.createElement('td', null, pt.x.toFixed(2)),
                            React.createElement('td', null, pt.y.toFixed(2)),
                            React.createElement('td', null, Number(wz).toFixed(2)),
                            React.createElement('td', { style: { color: 'var(--es-info)' } }, mapPt.x.toFixed(1)),
                            React.createElement('td', { style: { color: 'var(--es-info)' } }, mapPt.y.toFixed(1))
                        );
                    })
                )
            )
        )
    );
}

function ZoneConfigForm({ selected, onUpdate }) {
    return React.createElement(React.Fragment, null,
        React.createElement(EditorField, {
            label: 'Label',
            value: selected.label,
            onChange: (value) => onUpdate(selected.id, { label: value })
        }),
        React.createElement(EditorSelect, {
            label: 'Mode',
            value: selected.mode,
            options: ['fixed', 'dynamic'],
            onChange: (value) => onUpdate(selected.id, { mode: value })
        }),
        selected.mode === 'fixed' ? React.createElement(EditorField, {
            label: 'Weather',
            value: selected.weather,
            onChange: (value) => onUpdate(selected.id, { weather: value })
        }) : React.createElement(EditorField, {
            label: 'Weathers (comma)',
            value: selected.weathers.join(', '),
            onChange: (value) => onUpdate(selected.id, { weathers: value.split(',').map(s => s.trim()).filter(Boolean) })
        }),
        selected.mode === 'dynamic' ? React.createElement(EditorField, {
            label: 'Interval (mins)',
            value: String(selected.intervalMinutes),
            onChange: (value) => onUpdate(selected.id, { intervalMinutes: Number(value) || 1 })
        }) : null,
        React.createElement(EditorField, {
            label: 'Thickness',
            value: String(selected.thickness),
            onChange: (value) => onUpdate(selected.id, { thickness: Number(value) || 1 })
        }),
        React.createElement(EditorField, {
            label: 'ID',
            value: selected.id,
            readOnly: true
        })
    );
}

function ZonePointsList({ selected }) {
    return React.createElement('div', { className: 'es-points-list' },
        React.createElement('div', { className: 'es-points-header' },
            React.createElement('span', null, '#'),
            React.createElement('span', null, 'X'),
            React.createElement('span', null, 'Y')
        ),
        selected.points.map((pt, i) => React.createElement('div', { key: i, className: 'es-point-row' },
            React.createElement('span', { className: 'es-point-index' }, i + 1),
            React.createElement('span', { className: 'es-point-val' }, pt.x.toFixed(1)),
            React.createElement('span', { className: 'es-point-val' }, pt.y.toFixed(1))
        ))
    );
}

function EditorField({ label, value, onChange, readOnly }) {
    return React.createElement('div', { className: 'es-editor-group' },
        React.createElement('div', { className: 'es-editor-label' }, label),
        React.createElement('input', {
            className: 'es-editor-input',
            value: value,
            readOnly: !!readOnly,
            onChange: onChange ? (e) => onChange(e.target.value) : undefined
        })
    );
}

function EditorSelect({ label, value, options, onChange }) {
    return React.createElement('div', { className: 'es-editor-group' },
        React.createElement('div', { className: 'es-editor-label' }, label),
        React.createElement('div', { className: 'es-editor-select' },
            options.map(option => React.createElement('button', {
                key: option,
                className: `es-editor-pill${option === value ? ' active' : ''}`,
                onClick: () => onChange(option)
            }, option))
        )
    );
}

function EditorHelp() {
    return React.createElement('div', { className: 'es-editor-help' },
        React.createElement('div', { className: 'es-editor-label' }, 'MAP CONTROLS'),
        React.createElement('div', { className: 'es-editor-help-line' }, React.createElement('strong', null, 'Draw Mode:'), ' Click map to add points'),
        React.createElement('div', { className: 'es-editor-help-line' }, 'Right-click point: remove'),
        React.createElement('div', { className: 'es-editor-help-line' }, 'Drag points: move'),
        React.createElement('div', { className: 'es-editor-help-line' }, 'Scroll: zoom, drag map: pan'),
        React.createElement('div', { className: 'es-editor-help-line' }, React.createElement('strong', null, 'Calibrate:'), ' Links map to game world. Stand in-game, then click corresponding spot on map (2 points needed).')
    );
}

function CalibrationOverlay({ calibration, onCancel }) {
    if (!calibration || !calibration.active) return null;

    const isPickAnchor = calibration.stage === 'pickAnchor';
    const isPickPoint = calibration.stage === 'pickPoint';

    const title = isPickAnchor ? 'STEP 1: Place Anchor A' : 'STEP 2: Place Anchor B';
    const instruction = isPickAnchor
        ? 'Stand at your first reference point in-game, then CLICK that location on this map.'
        : 'Move to your second reference point in-game, then CLICK that location on this map.';

    return React.createElement('div', { className: 'es-calibration-overlay' },
        React.createElement('div', { className: 'es-calibration-box' },
            React.createElement('div', { className: 'es-calibration-title' }, title),
            React.createElement('div', { className: 'es-calibration-instruction' }, instruction),
            React.createElement('div', { className: 'es-calibration-hint' },
                isPickAnchor
                    ? 'Tip: Choose two points far apart for best accuracy (e.g., opposite corners of the map)'
                    : 'Anchor A is marked. Now place Anchor B at a different location.'
            ),
            React.createElement('button', {
                className: 'es-calibration-cancel',
                onClick: onCancel
            }, 'Cancel (ESC)')
        )
    );
}

function EditorMap({ zones, selectedId, onSelect, onUpdate, onAddPoint, onRemovePoint, onCalibrateAnchor, onCalibratePoint, calibration, onCancelCalibration, view, setView, minScaleRef, bounds, mapUrl, mapSize, drawMode }) {
    const mapRef = useRef(null);
    const containerRef = useRef(null);
    const draggingRef = useRef(null);

    const imageUrl = mapUrl || WEATHER_EDITOR_MAP_URL;

    const toMapCoords = useCallback((point) => {
        return {
            x: ((point.x - bounds.minX) / (bounds.maxX - bounds.minX)) * mapSize,
            y: (1 - (point.y - bounds.minY) / (bounds.maxY - bounds.minY)) * mapSize,
            z: point.z || 0
        };
    }, [bounds, mapSize]);

    const toWorldCoords = useCallback((x, y) => {
        const worldX = bounds.minX + (x / mapSize) * (bounds.maxX - bounds.minX);
        const worldY = bounds.minY + ((mapSize - y) / mapSize) * (bounds.maxY - bounds.minY);
        return { x: worldX, y: worldY };
    }, [bounds, mapSize]);

    const handleWheel = useCallback((event) => {
        event.preventDefault();
        const delta = event.deltaY * -0.001;
        const minScale = (minScaleRef && minScaleRef.current) || 0.1;
        const oldScale = view.scale;
        const nextScale = Math.max(minScale, Math.min(3, oldScale + delta));

        if (nextScale === oldScale) return;

        // Get cursor position relative to the map container
        const rect = event.currentTarget.getBoundingClientRect();
        const cursorX = event.clientX - rect.left;
        const cursorY = event.clientY - rect.top;

        // Calculate the point on the map that's under the cursor
        const mapPointX = (cursorX - view.x) / oldScale;
        const mapPointY = (cursorY - view.y) / oldScale;

        // Calculate new view position to keep the same map point under cursor
        const newX = cursorX - (mapPointX * nextScale);
        const newY = cursorY - (mapPointY * nextScale);

        setView({ x: newX, y: newY, scale: nextScale });
    }, [setView, view.scale, view.x, view.y, minScaleRef]);

    const handlePointerDown = useCallback((event, type, payload) => {
        event.preventDefault();
        event.stopPropagation();
        draggingRef.current = {
            type: type,
            payload: payload,
            startX: event.clientX,
            startY: event.clientY,
            baseX: view.x,
            baseY: view.y
        };
    }, [view.x, view.y]);

    const handleMapPointerDown = useCallback((event) => {
        if (event.button !== 0) return;
        if (event.target !== event.currentTarget) return;
        handlePointerDown(event, 'pan');
    }, [handlePointerDown]);

    const handlePointerMove = useCallback((event) => {
        if (!draggingRef.current) return;

        if (draggingRef.current.type === 'pan') {
            const dx = event.clientX - draggingRef.current.startX;
            const dy = event.clientY - draggingRef.current.startY;
            setView(prev => ({ ...prev, x: draggingRef.current.baseX + dx, y: draggingRef.current.baseY + dy }));
            return;
        }

        if (draggingRef.current.type === 'point') {
            if (!mapRef.current) return;
            const rect = mapRef.current.getBoundingClientRect();
            const localX = (event.clientX - rect.left - view.x) / view.scale;
            const localY = (event.clientY - rect.top - view.y) / view.scale;
            const clampedX = Math.max(0, Math.min(mapSize, localX));
            const clampedY = Math.max(0, Math.min(mapSize, localY));

            const world = toWorldCoords(clampedX, clampedY);
            const target = draggingRef.current.payload;
            const targetZone = zones.find(z => z.id === target.zoneId);
            if (!targetZone) return;

            onUpdate(target.zoneId, {
                points: targetZone.points.map((pt, idx) => {
                    if (idx !== target.index) return pt;
                    return { x: world.x, y: world.y, z: pt.z || 0 };
                })
            });
        }
    }, [mapSize, onUpdate, toWorldCoords, view.scale, view.x, view.y, zones]);

    const handlePointerUp = useCallback(() => {
        draggingRef.current = null;
    }, []);

    useEffect(() => {
        window.addEventListener('pointermove', handlePointerMove);
        window.addEventListener('pointerup', handlePointerUp);
        return () => {
            window.removeEventListener('pointermove', handlePointerMove);
            window.removeEventListener('pointerup', handlePointerUp);
        };
    }, [handlePointerMove, handlePointerUp]);

    // Attach wheel listener with passive: false to allow preventDefault
    useEffect(() => {
        const container = containerRef.current;
        if (!container) return;

        container.addEventListener('wheel', handleWheel, { passive: false });
        return () => {
            container.removeEventListener('wheel', handleWheel);
        };
    }, [handleWheel]);

    return React.createElement('div', {
        ref: containerRef,
        className: `es-editor-map${calibration && calibration.active ? ' calibrating' : ''}${drawMode ? ' drawing' : ''}`,
        onPointerDown: handleMapPointerDown,
        onContextMenu: (event) => event.preventDefault()
    },
        drawMode && React.createElement('div', { className: 'es-draw-indicator' }, 'DRAW MODE ACTIVE'),
        React.createElement('div', {
            className: 'es-map-transform-layer',
            ref: mapRef,
            style: {
                width: `${mapSize}px`,
                height: `${mapSize}px`,
                transform: `translate(${view.x}px, ${view.y}px) scale(${view.scale})`
            }
        },
            React.createElement('img', {
                src: imageUrl,
                className: 'es-map-image',
                draggable: false,
                width: mapSize,
                height: mapSize
            }),
            React.createElement('svg', {
                className: 'es-map-svg',
                viewBox: `0 0 ${mapSize} ${mapSize}`,
                onPointerDown: (event) => {
                    if (event.button !== 0) return;
                    if (event.target !== event.currentTarget) return;

                    const rect = mapRef.current.getBoundingClientRect();
                    const localX = (event.clientX - rect.left - view.x) / view.scale;
                    const localY = (event.clientY - rect.top - view.y) / view.scale;
                    const clampedX = Math.max(0, Math.min(mapSize, localX));
                    const clampedY = Math.max(0, Math.min(mapSize, localY));

                    if (calibration && calibration.active) {
                        const mapPoint = { x: clampedX, y: clampedY };
                        if (calibration.stage === 'pickAnchor') {
                            onCalibrateAnchor(mapPoint);
                        } else if (calibration.stage === 'pickPoint') {
                            onCalibratePoint(mapPoint);
                        }
                        return;
                    }

                    if (!selectedId || !drawMode) return;
                    const world = toWorldCoords(clampedX, clampedY);
                    onAddPoint(selectedId, { x: world.x, y: world.y, z: 0 });
                }
            },
                zones.map(zone => {
                    const isSelected = zone.id === selectedId;
                    const points = zone.points.map(pt => toMapCoords(pt));
                    const polygonPoints = points.map(pt => `${pt.x},${pt.y}`).join(' ');
                    return React.createElement(React.Fragment, { key: zone.id },
                        React.createElement('polygon', {
                            className: `zone-poly${isSelected ? ' selected' : ''}`,
                            points: polygonPoints,
                            onPointerDown: (event) => {
                                event.stopPropagation();
                                onSelect(zone.id);
                            }
                        }),
                        isSelected && points.map((pt, idx) => React.createElement('circle', {
                            key: `${zone.id}:${idx}`,
                            className: 'zone-handle',
                            cx: pt.x,
                            cy: pt.y,
                            r: 5,
                            onPointerDown: (event) => handlePointerDown(event, 'point', { zoneId: zone.id, index: idx }),
                            onContextMenu: (event) => {
                                event.preventDefault();
                                onRemovePoint(zone.id, idx);
                            }
                        }))
                    );
                }),
                calibration && calibration.anchor && calibration.anchor.map
                    ? React.createElement(React.Fragment, null,
                        React.createElement('circle', {
                            className: 'calibration-anchor',
                            cx: calibration.anchor.map.x,
                            cy: calibration.anchor.map.y,
                            r: 10
                        }),
                        React.createElement('text', {
                            className: 'calibration-label',
                            x: calibration.anchor.map.x + 12,
                            y: calibration.anchor.map.y + 4
                        }, 'A')
                    )
                    : null
            ) // end svg
        ), // end transform-layer
        calibration && calibration.active
            ? React.createElement(CalibrationOverlay, { calibration, onCancel: onCancelCalibration })
            : null
    ); // end outer div
}

// ============================================================================
// RESOLUTION SCALING
// ============================================================================

function clamp(n, min, max) {
    return Math.max(min, Math.min(max, n));
}

function getUiScale() {
    // FiveM/NUI renders at actual screen pixel size.
    // Use 1080p height as baseline, clamped up to 4K.
    const h = window.innerHeight || 1080;
    const normalized = h / 1080;
    return clamp(normalized, 1, 2);
}

function getSettingsUiScale() {
    const h = window.innerHeight || 1080;
    return clamp(h / 1080, 0.86, 1);
}

function applyUiScale(value) {
    document.documentElement.style.setProperty('--es-ui-scale', value);
    document.documentElement.style.setProperty('--es-settings-scale', getSettingsUiScale());
}

applyUiScale(getUiScale());
window.addEventListener('resize', () => applyUiScale(getUiScale()));

// ============================================================================
// DEBUG UTILITIES
// ============================================================================

const debugParams = new URLSearchParams(window.location.search);
const uiDebugEnabled = debugParams.get('debug') === '1' || debugParams.get('debug') === 'true';

function uiDebugLog(...args) {
    if (!uiDebugEnabled) return;
    // eslint-disable-next-line no-console
    console.log('[cortex-lib/ui]', ...args);
}

function safeJson(value) {
    try {
        return JSON.stringify(value);
    } catch (e) {
        return '[unserializable]';
    }
}

if (uiDebugEnabled) {
    window.__cortex = window.__cortex || {};
    window.__cortex.debug = {
        enabled: true,
        push(action, data) {
            window.postMessage({ action, data }, '*');
        },
        notify(data) {
            window.postMessage({ action: 'notify', data }, '*');
        },
        clear() {
            window.postMessage({ action: 'clearNotifications' }, '*');
        },
        hide(id) {
            window.postMessage({ action: 'hideNotify', data: { id } }, '*');
        },
        progressStart(data) {
            window.postMessage({ action: 'progressStart', data }, '*');
        },
        progressEnd() {
            window.postMessage({ action: 'progressEnd' }, '*');
        },
        alertDialog(data) {
            window.postMessage({ action: 'alertDialog', data }, '*');
        },
        textUIShow(data) {
            window.postMessage({ action: 'textUIShow', data }, '*');
        },
        textUIHide() {
            window.postMessage({ action: 'textUIHide' }, '*');
        }
    };

    uiDebugLog('Debug enabled. Try in console:', 'window.__cortex.debug.menu()', 'window.__cortex.debug.notify({ description: "Hello" })');
}

// ============================================================================
// ICONS
// ============================================================================

const icons = {
    success: React.createElement('svg', { viewBox: '0 0 24 24', width: 16, height: 16, fill: 'none', stroke: 'currentColor', strokeWidth: 2 },
        React.createElement('path', { d: 'M20 6L9 17l-5-5' })
    ),
    error: React.createElement('svg', { viewBox: '0 0 24 24', width: 16, height: 16, fill: 'none', stroke: 'currentColor', strokeWidth: 2 },
        React.createElement('circle', { cx: 12, cy: 12, r: 10 }),
        React.createElement('path', { d: 'M15 9l-6 6M9 9l6 6' })
    ),
    warning: React.createElement('svg', { viewBox: '0 0 24 24', width: 16, height: 16, fill: 'none', stroke: 'currentColor', strokeWidth: 2 },
        React.createElement('path', { d: 'M12 9v4M12 17h.01' }),
        React.createElement('path', { d: 'M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z' })
    ),
    info: React.createElement('svg', { viewBox: '0 0 24 24', width: 16, height: 16, fill: 'none', stroke: 'currentColor', strokeWidth: 2 },
        React.createElement('circle', { cx: 12, cy: 12, r: 10 }),
        React.createElement('path', { d: 'M12 16v-4M12 8h.01' })
    )
};

icons.inform = icons.info;

// ============================================================================
// NOTIFICATION COMPONENT
// ============================================================================

function Notification({ id, type, title, description, duration, showDuration, persistent, plain, hideIcon, onRemove }) {
    const [exiting, setExiting] = useState(false);
    const timeoutRef = useRef(null);

    const handleRemove = useCallback(() => {
        setExiting(true);
        setTimeout(() => onRemove(id), 150);
    }, [id, onRemove]);

    useEffect(() => {
        if (duration > 0 && !persistent) {
            timeoutRef.current = setTimeout(handleRemove, duration);
        }
        return () => {
            if (timeoutRef.current) {
                clearTimeout(timeoutRef.current);
            }
        };
    }, [duration, persistent, handleRemove]);

    const notifyType = type || 'info';
    const icon = icons[notifyType] || icons.info;
    const showBar = showDuration !== false && duration > 0;
    const showIcon = hideIcon !== true;

    const className = `notify ${notifyType}${persistent ? ' persistent' : ''}${plain ? ' notify-plain' : ''}${exiting ? ' exiting' : ''}`;

    return React.createElement('div', { className, 'data-id': id },
        showIcon && React.createElement('div', { className: 'notify-icon' }, icon),
        React.createElement('div', { className: 'notify-content' },
            title && React.createElement('div', { className: 'notify-title' }, title),
            description && React.createElement('div', { className: 'notify-description' }, description)
        ),
        persistent && React.createElement('button', {
            className: 'notify-close',
            'aria-label': 'Close',
            onClick: (e) => {
                e.stopPropagation();
                handleRemove();
            }
        }, '\u00D7'),
        showBar && React.createElement('div', {
            className: 'notify-duration',
            style: { animation: `shrink ${duration}ms linear forwards` }
        })
    );
}

// ============================================================================
// NOTIFICATION CONTAINER
// ============================================================================

function NotificationContainer({ notifications, position, onRemove }) {
    return React.createElement('div', { id: 'notify-container', className: position || 'top-right' },
        notifications.map(notif =>
            React.createElement(Notification, {
                key: `${notif.id}-${notif.refreshTick || 0}`,
                ...notif,
                onRemove
            })
        )
    );
}

// ============================================================================
// DEBUG PANEL
// ============================================================================

function DebugPanelLine({ line }) {
    if (typeof line === 'string') {
        return React.createElement('div', { className: 'es-debug-line' }, line);
    }

    const label = line?.label;
    let value = line?.value;

    if (value == null) value = '';
    if (typeof value === 'object') value = safeJson(value);

    return React.createElement('div', { className: 'es-debug-line' },
        React.createElement('span', { className: 'es-debug-label' }, label || ''),
        React.createElement('span', { className: 'es-debug-value', style: line?.color ? { color: line.color } : undefined }, String(value))
    );
}

function DebugPanel({ open, title, subtitle, position, lines, data }) {
    if (!open) return null;

    const rootClass = `es-debug-root ${position || 'top-right'}`;
    const hasData = data && typeof data === 'object';

    return React.createElement('div', { className: rootClass },
        React.createElement('div', { className: 'es-debug-panel' },
            React.createElement('div', { className: 'es-debug-header' },
                React.createElement('div', { className: 'es-debug-title' }, title || 'DEBUG'),
                subtitle ? React.createElement('div', { className: 'es-debug-subtitle' }, subtitle) : null
            ),
            React.createElement('div', { className: 'es-debug-body' },
                Array.isArray(lines)
                    ? lines.map((line, idx) => React.createElement(DebugPanelLine, { key: idx, line }))
                    : null,
                hasData ? React.createElement('pre', { className: 'es-debug-json' }, safeJson(data)) : null
            )
        )
    );
}

// ============================================================================
// PROGRESS BAR COMPONENT
// ============================================================================

function ProgressBar({ active, duration, label, position, style, canCancel }) {
    const [progressPct, setProgressPct] = useState(0);
    const rafRef = useRef(null);
    const activeRef = useRef(false);

    useEffect(() => {
        activeRef.current = Boolean(active);

        if (rafRef.current) {
            cancelAnimationFrame(rafRef.current);
            rafRef.current = null;
        }

        if (!active) {
            setProgressPct(0);
            return;
        }

        if (!duration || duration <= 0) {
            setProgressPct(100);
            return;
        }

        const start = performance.now();
        setProgressPct(0);

        const step = (now) => {
            if (!activeRef.current) return;
            const t = Math.min(1, (now - start) / duration);
            setProgressPct(t * 100);
            if (t < 1) {
                rafRef.current = requestAnimationFrame(step);
            }
        };

        rafRef.current = requestAnimationFrame(step);

        return () => {
            activeRef.current = false;
            if (rafRef.current) {
                cancelAnimationFrame(rafRef.current);
                rafRef.current = null;
            }
        };
    }, [active, duration]);

    const containerClass = `progress-container ${position || 'bottom'}${active ? ' active' : ''}`;
    const effectiveStyle = style || 'bar';

    const showCircle = effectiveStyle === 'circle';
    const showBar = !showCircle;

    const pctClamped = Math.max(0, Math.min(100, progressPct));
    const pctText = `${Math.round(pctClamped)}%`;
    const pctSmooth = `${pctClamped}%`;

    const barStyle = { width: pctSmooth };

    const circleR = 45;
    const circleC = 2 * Math.PI * circleR;
    const circleOffset = circleC * (1 - (pctClamped / 100));

    return React.createElement('div', { id: 'progress-container', className: containerClass },
        React.createElement('div', { className: 'progress-wrapper' },
            showBar && React.createElement('div', { className: 'progress-track' },
                React.createElement('div', {
                    id: 'progress-bar',
                    className: 'progress-fill',
                    style: barStyle
                })
            ),
            showCircle && React.createElement('div', { className: 'progress-circle' },
                React.createElement('svg', {
                    className: 'progress-circle-svg',
                    viewBox: '0 0 100 100'
                },
                    React.createElement('circle', {
                        className: 'progress-circle-track',
                        cx: 50,
                        cy: 50,
                        r: circleR
                    }),
                    React.createElement('circle', {
                        className: 'progress-circle-fill',
                        cx: 50,
                        cy: 50,
                        r: circleR,
                        style: {
                            strokeDasharray: circleC,
                            strokeDashoffset: circleOffset
                        }
                    })
                ),
                React.createElement('div', { className: 'progress-circle-center' }),
                React.createElement('div', { className: 'progress-circle-text' }, pctText)
            ),
            React.createElement('div', { id: 'progress-label', className: 'progress-label' }, label || ''),
            React.createElement('div', {
                id: 'progress-cancel',
                className: 'progress-cancel',
                style: { display: canCancel ? 'block' : 'none' }
            }, 'Right-click to cancel')
        )
    );
}

// ============================================================================
// TEXT UI COMPONENT
// ============================================================================

const textUiIcons = {
    hand: React.createElement('svg', { viewBox: '0 0 24 24', width: 16, height: 16, fill: 'none', stroke: 'currentColor', strokeWidth: 2 },
        React.createElement('path', { d: 'M7 11V7a2 2 0 114 0v4' }),
        React.createElement('path', { d: 'M11 11V5a2 2 0 114 0v6' }),
        React.createElement('path', { d: 'M15 11V6a2 2 0 114 0v8a6 6 0 01-6 6H9a6 6 0 01-6-6V9a2 2 0 114 0v2' })
    )
};

function isTextUiPlateStyleKey(key) {
    const k = String(key).toLowerCase();
    if (k === 'background' || k === 'backgroundcolor' || k === 'backgroundimage') return true;
    if (k === 'boxshadow' || k === 'outline' || k === 'backdropfilter' || k === 'webkitbackdropfilter') return true;
    if (k.startsWith('border')) return true;
    return false;
}

function partitionTextUiStyle(style, backdrop) {
    if (!style || typeof style !== 'object') return { outer: undefined };
    if (backdrop) return { outer: style };
    const outer = {};
    for (const key of Object.keys(style)) {
        if (isTextUiPlateStyleKey(key)) continue;
        outer[key] = style[key];
    }
    return { outer: Object.keys(outer).length ? outer : undefined };
}

function TextUI({ open, text, position, icon, style, backdrop }) {
    if (!open) return null;

    const iconEl = icon ? (textUiIcons[icon] || null) : null;
    const className = `textui ${position || 'bottom-center'}${iconEl ? ' has-icon' : ''}${backdrop ? ' textui-backdrop' : ''}`;
    const { outer: outerStyle } = partitionTextUiStyle(style, Boolean(backdrop));

    return React.createElement('div', {
        id: 'textui',
        className,
        style: outerStyle
    },
        iconEl && React.createElement('div', { className: 'textui-icon' }, iconEl),
        React.createElement('div', { className: 'textui-text' }, text)
    );
}

// ============================================================================
// MENU COMPONENT
// ============================================================================

const menuKeyMap = {
    up: ['ArrowUp'],
    down: ['ArrowDown'],
    left: ['ArrowLeft'],
    right: ['ArrowRight'],
    select: ['Enter'],
    toggle: [' '],
    back: ['Escape', 'Backspace']
};

function normalizeOption(option) {
    const values = Array.isArray(option.values) ? option.values : null;
    const hasValues = Boolean(values && values.length);
    const hasCheck = typeof option.checked === 'boolean';

    const defaultIndex = typeof option.defaultIndex === 'number' ? option.defaultIndex : 1;
    const scrollIndex = hasValues ? Math.max(1, Math.min(defaultIndex, values.length)) : 1;

    return {
        label: option.label || '',
        description: option.description || '',
        icon: option.icon || null,
        iconColor: option.iconColor || null,
        progress: typeof option.progress === 'number' ? option.progress : null,
        values,
        hasValues,
        checked: hasCheck ? option.checked : null,
        hasCheck,
        scrollIndex,
        close: option.close !== false
    };
}

function getValueLabel(value) {
    if (typeof value === 'string') return value;
    if (value && typeof value === 'object') return value.label || '';
    return '';
}

function getValueDescription(value) {
    if (value && typeof value === 'object') return value.description || '';
    return '';
}

async function nuiPost(name, payload) {
    try {
        const res = await fetch(`https://${GetParentResourceName()}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(payload || {})
        });
        return await res.json().catch(() => ({}));
    } catch (e) {
        uiDebugLog('nui post failed', name, e);
        return {};
    }
}

function Menu({ open, id, title, subtitle, position, canClose, disableInput, options, selected, tooltip, setMenu }) {
    const bodyRef = useRef(null);
    const optionsRef = useRef([]);
    const selectedRef = useRef(1);

    useEffect(() => {
        optionsRef.current = options;
        selectedRef.current = selected;
    }, [options, selected]);


    const setSelectedIndex = useCallback((next, secondary) => {
        const opts = optionsRef.current;
        if (!opts.length) return;

        let clamped = next;

        // Wrap-around navigation
        if (clamped < 1) clamped = opts.length;
        if (clamped > opts.length) clamped = 1;

        clamped = Math.max(1, Math.min(clamped, opts.length));
        if (clamped === selectedRef.current && secondary == null) return;

        const opt = opts[clamped - 1];
        selectedRef.current = clamped;
        setMenu(prev => {
            const nextTooltip = opt?.description || '';
            return { ...prev, selected: clamped, tooltip: nextTooltip };
        });

        nuiPost('es_menu_selected', {
            id,
            selected: clamped,
            secondary: secondary ?? false
        });
    }, [id, setMenu]);

    const closeMenu = useCallback(async (keyPressed) => {
        if (!canClose) return;
        await nuiPost('es_menu_close', { id, keyPressed: keyPressed || null });
        setMenu(prev => ({ ...prev, open: false, id: null }));
    }, [id, canClose, setMenu]);

    const doSideScroll = useCallback((direction) => {
        const opts = optionsRef.current;
        const idx = selectedRef.current - 1;
        const opt = opts[idx];
        if (!opt || !opt.hasValues) return;

        const currentIndex = opt.scrollIndex || 1;
        const nextIndex = ((currentIndex - 1 + direction + opt.values.length) % opt.values.length) + 1;

        const nextOption = { ...opt, scrollIndex: nextIndex };
        opts[idx] = nextOption;

        const currentValue = opt.values[nextIndex - 1];
        const valueDescription = getValueDescription(currentValue);

        setMenu(prev => ({
            ...prev,
            options: opts.slice(0),
            tooltip: valueDescription || opt.description || ''
        }));

        nuiPost('es_menu_sideScroll', {
            id,
            selected: idx + 1,
            scrollIndex: nextIndex
        });
    }, [id, setMenu]);

    const toggleCheck = useCallback(() => {
        const opts = optionsRef.current;
        const idx = selectedRef.current - 1;
        const opt = opts[idx];
        if (!opt || !opt.hasCheck) return;

        const nextChecked = !opt.checked;
        const nextOption = { ...opt, checked: nextChecked };
        opts[idx] = nextOption;

        setMenu(prev => ({ ...prev, options: opts.slice(0) }));

        nuiPost('es_menu_check', {
            id,
            selected: idx + 1,
            checked: nextChecked
        });
    }, [id, setMenu]);

    const submit = useCallback(async () => {
        const opts = optionsRef.current;
        const idx = selectedRef.current - 1;
        const opt = opts[idx];
        if (!opt) return;

        const res = await nuiPost('es_menu_submit', {
            id,
            selected: idx + 1,
            scrollIndex: opt.scrollIndex || 1
        });

        if (res && res.close) {
            setMenu(prev => ({ ...prev, open: false, id: null }));
        }
    }, [id, setMenu]);

    useEffect(() => {
        const handleKeyDown = (e) => {
            if (!open) return;

            const key = e.key;

            if (menuKeyMap.up.includes(key)) {
                e.preventDefault();
                setSelectedIndex(selectedRef.current - 1);
                return;
            }

            if (menuKeyMap.down.includes(key)) {
                e.preventDefault();
                setSelectedIndex(selectedRef.current + 1);
                return;
            }

            if (menuKeyMap.left.includes(key)) {
                e.preventDefault();
                doSideScroll(-1);
                return;
            }

            if (menuKeyMap.right.includes(key)) {
                e.preventDefault();
                doSideScroll(1);
                return;
            }

            if (menuKeyMap.select.includes(key)) {
                e.preventDefault();
                submit();
                return;
            }

            if (menuKeyMap.toggle.includes(key)) {
                e.preventDefault();
                toggleCheck();
                return;
            }

            if (menuKeyMap.back.includes(key)) {
                e.preventDefault();
                closeMenu(key);
            }
        };

        window.addEventListener('keydown', handleKeyDown, { passive: false });
        return () => window.removeEventListener('keydown', handleKeyDown);
    }, [open, setSelectedIndex, doSideScroll, submit, toggleCheck, closeMenu]);

    // Best-effort controller support via key events synthesized by browser
    // (FiveM usually routes gamepad as keyboard for NUI focus).

    useEffect(() => {
        if (!open) return;
        if (!bodyRef.current) return;

        const body = bodyRef.current;
        const active = body.querySelector('.es-menu-option.active');
        if (!active) return;

        const bodyRect = body.getBoundingClientRect();
        const activeRect = active.getBoundingClientRect();

        const outTop = activeRect.top < bodyRect.top;
        const outBottom = activeRect.bottom > bodyRect.bottom;

        if (outTop || outBottom) {
            active.scrollIntoView({ block: 'nearest' });
        }
    }, [open, selected, options.length]);

    if (!open) return null;

    const rootClass = `es-menu-root ${position || 'top-left'}${disableInput ? ' input-disabled' : ''}`;


    return React.createElement('div', {
        className: rootClass,
        onMouseDown: (e) => {
            if (e.target === e.currentTarget) {
                closeMenu('Escape');
            }
        }
    },
        React.createElement('div', { className: 'es-menu' },
            React.createElement('div', { className: 'es-menu-header' },
                React.createElement('div', { className: 'es-menu-title' }, title || ''),
                subtitle ? React.createElement('div', { className: 'es-menu-subtitle' }, subtitle) : null
            ),
            React.createElement('div', { className: 'es-menu-body', ref: bodyRef },
                options.map((opt, i) => {
                    const optionIndex = i + 1;
                    const active = optionIndex === selected;
                    const value = opt.hasValues ? opt.values[(opt.scrollIndex || 1) - 1] : null;
                    const valueLabel = value ? getValueLabel(value) : '';

                    const rightBadge = opt.hasCheck
                        ? (opt.checked ? 'ON' : 'OFF')
                        : (opt.hasValues ? valueLabel : '');

                    return React.createElement('div', {
                        key: `${id || 'menu'}:${optionIndex}:${opt.label}`,
                        className: `es-menu-option${active ? ' active' : ''}`,
                        onMouseEnter: () => setSelectedIndex(optionIndex),
                        onMouseDown: (e) => { e.preventDefault(); e.stopPropagation(); },
                        onClick: (e) => { e.preventDefault(); e.stopPropagation(); submit(); }
                    },
                        React.createElement('div', { className: 'es-menu-option-main' },
                            React.createElement('div', { className: 'es-menu-option-label' }, opt.label),
                            opt.progress != null ? React.createElement('div', { className: 'es-menu-option-progress' },
                                React.createElement('div', {
                                    className: 'es-menu-option-progressFill',
                                    style: { width: `${Math.max(0, Math.min(100, opt.progress))}%` }
                                })
                            ) : null
                        ),
                        rightBadge ? React.createElement('div', { className: 'es-menu-option-badge' }, rightBadge) : null
                    );
                })
            ),
            React.createElement('div', { className: 'es-menu-footer' },
                React.createElement('div', { className: 'es-menu-tooltip' }, tooltip || ''),
                React.createElement('div', { className: 'es-menu-hints' },
                    React.createElement('span', null, 'Enter: Select'),
                    React.createElement('span', null, 'Arrows: Navigate'),
                    React.createElement('span', null, 'Esc/Back: Close')
                )
            )
        )
    );
}

// ============================================================================
// ALERT DIALOG COMPONENT
// ============================================================================

function AlertDialog({ open, header, content, centered, cancel, labels, style, onClose }) {
    const confirmLabel = labels?.confirm || 'CONFIRM';
    const cancelLabel = labels?.cancel || 'CANCEL';

    useEffect(() => {
        if (!open) return;

        const onKeyDown = (e) => {
            if (e.key === 'Escape') {
                onClose('cancel');
            }
            if (e.key === 'Enter') {
                onClose('confirm');
            }
        };

        window.addEventListener('keydown', onKeyDown);
        return () => window.removeEventListener('keydown', onKeyDown);
    }, [open, onClose]);

    if (!open) return null;

    const dialogClass = `alert-dialog${centered ? ' centered' : ''}`;

    return React.createElement('div', {
        className: 'alert-overlay',
        onMouseDown: () => onClose('cancel')
    },
        React.createElement('div', {
            className: dialogClass,
            onMouseDown: (e) => e.stopPropagation(),
            onClick: (e) => e.stopPropagation(),
            onContextMenu: (e) => e.preventDefault()
        },

            header && React.createElement('div', { className: 'alert-header' }, header),
            content && React.createElement('div', { className: 'alert-content' }, content),
            React.createElement('div', { className: 'alert-actions' },
                cancel && React.createElement('button', {
                    className: 'alert-btn cancel',
                    onClick: () => onClose('cancel')
                }, cancelLabel),
                React.createElement('button', {
                    className: 'alert-btn confirm',
                    onClick: () => onClose('confirm')
                }, confirmLabel)
            )
        )
    );
}

function HelpBar({ open, items }) {
    if (!open || !items || !items.length) return null;

    return React.createElement('div', { className: 'es-help-bar' },
        items.map((item, i) => React.createElement('div', { key: i, className: 'es-help-item' },
            React.createElement('div', { className: 'es-help-label' }, item.label),
            React.createElement('div', { className: 'es-help-values' },
                item.value.split(' ').map((key, j) =>
                    React.createElement('span', { key: j, className: 'es-help-key' }, key)
                )
            )
        ))
    );
}

// ============================================================================
// CONTEXT MENU COMPONENT (Settings-style dialog with form fields)
// ============================================================================

function ContextMenuCheckbox({ field, value, onChange }) {
    const handleClick = useCallback(() => {
        onChange(field.name, !value);
    }, [field.name, value, onChange]);

    return React.createElement('div', {
        className: 'es-context-checkbox',
        onClick: handleClick
    },
        React.createElement('div', { className: `es-context-checkbox-box${value ? ' checked' : ''}` },
            React.createElement('svg', { viewBox: '0 0 24 24' },
                React.createElement('path', { d: 'M20 6L9 17l-5-5' })
            )
        ),
        React.createElement('span', { className: 'es-context-checkbox-label' }, field.label)
    );
}

function ContextMenuSelect({ field, value, onChange }) {
    const [dropdownOpen, setDropdownOpen] = useState(false);
    const selectRef = useRef(null);

    const selectedOption = field.options?.find(opt => 
        (typeof opt === 'object' ? opt.value : opt) === value
    );
    const displayValue = selectedOption 
        ? (typeof selectedOption === 'object' ? selectedOption.label : selectedOption)
        : (value || 'Select...');

    const handleSelect = useCallback((optValue) => {
        onChange(field.name, optValue);
        setDropdownOpen(false);
    }, [field.name, onChange]);

    useEffect(() => {
        if (!dropdownOpen) return;
        const handleClickOutside = (e) => {
            if (selectRef.current && !selectRef.current.contains(e.target)) {
                setDropdownOpen(false);
            }
        };
        document.addEventListener('mousedown', handleClickOutside);
        return () => document.removeEventListener('mousedown', handleClickOutside);
    }, [dropdownOpen]);

    return React.createElement('div', { className: 'es-context-select', ref: selectRef },
        React.createElement('div', {
            className: 'es-context-select-trigger',
            onClick: () => setDropdownOpen(!dropdownOpen)
        },
            field.icon && React.createElement('div', { className: 'es-context-select-icon' }, field.icon),
            React.createElement('span', { className: 'es-context-select-value' }, displayValue),
            React.createElement('svg', { className: 'es-context-select-arrow', viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: 2 },
                React.createElement('path', { d: 'M6 9l6 6 6-6' })
            )
        ),
        dropdownOpen && React.createElement('div', { className: 'es-context-select-dropdown' },
            (field.options || []).map((opt, i) => {
                const optValue = typeof opt === 'object' ? opt.value : opt;
                const optLabel = typeof opt === 'object' ? opt.label : opt;
                const isSelected = optValue === value;
                return React.createElement('div', {
                    key: i,
                    className: `es-context-select-option${isSelected ? ' selected' : ''}`,
                    onClick: () => handleSelect(optValue)
                }, optLabel);
            })
        )
    );
}

function ContextMenuInput({ field, value, onChange }) {
    const handleChange = useCallback((e) => {
        onChange(field.name, e.target.value);
    }, [field.name, onChange]);

    return React.createElement('input', {
        className: 'es-context-input',
        type: field.inputType || 'text',
        placeholder: field.placeholder || '',
        value: value || '',
        onChange: handleChange
    });
}

function ContextMenu({ open, title, fields, values, labels, onClose }) {
    const [formValues, setFormValues] = useState({});
    const confirmLabel = labels?.confirm || 'CONFIRM';
    const cancelLabel = labels?.cancel || 'CANCEL';

    useEffect(() => {
        if (open && values) {
            setFormValues({ ...values });
        }
    }, [open, values]);

    const handleChange = useCallback((name, value) => {
        setFormValues(prev => ({ ...prev, [name]: value }));
    }, []);

    const handleConfirm = useCallback(() => {
        onClose('confirm', formValues);
    }, [formValues, onClose]);

    const handleCancel = useCallback(() => {
        onClose('cancel', null);
    }, [onClose]);

    useEffect(() => {
        if (!open) return;
        const onKeyDown = (e) => {
            if (e.key === 'Escape') {
                handleCancel();
            }
        };
        window.addEventListener('keydown', onKeyDown);
        return () => window.removeEventListener('keydown', onKeyDown);
    }, [open, handleCancel]);

    if (!open) return null;

    return React.createElement('div', {
        className: 'es-context-overlay',
        onMouseDown: handleCancel
    },
        React.createElement('div', {
            className: 'es-context-dialog',
            onMouseDown: (e) => e.stopPropagation(),
            onClick: (e) => e.stopPropagation()
        },
            title && React.createElement('div', { className: 'es-context-header' }, title),
            React.createElement('div', { className: 'es-context-body' },
                (fields || []).map((field, i) => {
                    const fieldValue = formValues[field.name];
                    
                    if (field.type === 'checkbox') {
                        return React.createElement('div', { key: i, className: 'es-context-field' },
                            React.createElement(ContextMenuCheckbox, {
                                field,
                                value: Boolean(fieldValue),
                                onChange: handleChange
                            })
                        );
                    }

                    if (field.type === 'select') {
                        return React.createElement('div', { key: i, className: 'es-context-field' },
                            React.createElement('div', { className: 'es-context-label' },
                                field.label,
                                field.required && React.createElement('span', { className: 'required' }, '*')
                            ),
                            field.description && React.createElement('div', { className: 'es-context-sublabel' }, field.description),
                            React.createElement(ContextMenuSelect, {
                                field,
                                value: fieldValue,
                                onChange: handleChange
                            })
                        );
                    }

                    if (field.type === 'input' || field.type === 'text') {
                        return React.createElement('div', { key: i, className: 'es-context-field' },
                            React.createElement('div', { className: 'es-context-label' },
                                field.label,
                                field.required && React.createElement('span', { className: 'required' }, '*')
                            ),
                            field.description && React.createElement('div', { className: 'es-context-sublabel' }, field.description),
                            React.createElement(ContextMenuInput, {
                                field,
                                value: fieldValue,
                                onChange: handleChange
                            })
                        );
                    }

                    return null;
                })
            ),
            React.createElement('div', { className: 'es-context-actions' },
                React.createElement('button', {
                    className: 'es-context-btn cancel',
                    onClick: handleCancel
                }, cancelLabel),
                React.createElement('button', {
                    className: 'es-context-btn confirm',
                    onClick: handleConfirm
                }, confirmLabel)
            )
        )
    );
}

// ============================================================================
// RADIAL MENU COMPONENT (SVG-based, ox_lib inspired)
// ============================================================================

const RADIAL_PAGE_ITEMS = 8;  // Max items per page
const RADIAL_SIZE = 350;       // SVG viewBox size
const RADIAL_CENTER = RADIAL_SIZE / 2;
const RADIAL_OUTER_RADIUS = RADIAL_CENTER;
const RADIAL_INNER_RADIUS = 45;
const RADIAL_ICON_RADIUS = RADIAL_CENTER * 0.58;
const RADIAL_GAP = 3;

function degToRad(deg) {
    return deg * (Math.PI / 180);
}

function polarToCartesian(centerX, centerY, radius, angleInDegrees) {
    const angleInRadians = degToRad(angleInDegrees - 90);
    return {
        x: centerX + (radius * Math.cos(angleInRadians)),
        y: centerY + (radius * Math.sin(angleInRadians))
    };
}

function describeArc(x, y, radius, startAngle, endAngle) {
    const start = polarToCartesian(x, y, radius, endAngle);
    const end = polarToCartesian(x, y, radius, startAngle);
    const largeArcFlag = endAngle - startAngle <= 180 ? '0' : '1';
    return [
        'M', start.x, start.y,
        'A', radius, radius, 0, largeArcFlag, 0, end.x, end.y
    ].join(' ');
}

function describeSector(cx, cy, outerRadius, innerRadius, startAngle, endAngle, gap) {
    const outerStart = polarToCartesian(cx, cy, outerRadius - gap, startAngle + gap * 0.3);
    const outerEnd = polarToCartesian(cx, cy, outerRadius - gap, endAngle - gap * 0.3);
    const innerStart = polarToCartesian(cx, cy, innerRadius + gap, startAngle + gap * 0.3);
    const innerEnd = polarToCartesian(cx, cy, innerRadius + gap, endAngle - gap * 0.3);
    
    const largeArc = endAngle - startAngle > 180 ? 1 : 0;
    
    return [
        'M', outerStart.x, outerStart.y,
        'A', outerRadius - gap, outerRadius - gap, 0, largeArc, 1, outerEnd.x, outerEnd.y,
        'L', innerEnd.x, innerEnd.y,
        'A', innerRadius + gap, innerRadius + gap, 0, largeArc, 0, innerStart.x, innerStart.y,
        'Z'
    ].join(' ');
}

function getRadialPointer(clientX, clientY, element, itemCount, visibleItemCount) {
    if (!element || visibleItemCount === 0) return { type: 'outside', index: -1 };

    const rect = element.getBoundingClientRect();
    const svgScale = rect.width / RADIAL_SIZE;
    if (!Number.isFinite(svgScale) || svgScale <= 0) return { type: 'outside', index: -1 };

    const dx = clientX - (rect.left + rect.width / 2);
    const dy = clientY - (rect.top + rect.height / 2);
    const distance = Math.sqrt(dx * dx + dy * dy) / svgScale;

    if (distance < RADIAL_INNER_RADIUS) return { type: 'center', index: -1 };
    if (distance > RADIAL_OUTER_RADIUS) return { type: 'outside', index: -1 };

    let angle = Math.atan2(dx, -dy) * (180 / Math.PI);
    if (angle < 0) angle += 360;

    const angleStep = 360 / itemCount;
    const index = Math.floor(angle / angleStep) % itemCount;
    if (index >= visibleItemCount) return { type: 'outside', index: -1 };
    return { type: 'item', index };
}

function RadialMenu({ open, id, items, canGoBack, visible, appearance }) {
    const [hoverIndex, setHoverIndex] = useState(-1);
    const [page, setPage] = useState(1);
    const [isVisible, setIsVisible] = useState(false);
    const radialSvgRef = useRef(null);

    // Reset page when items change or menu opens
    useEffect(() => {
        if (open) {
            setPage(1);
            setHoverIndex(-1);
            setIsVisible(true);
        } else {
            setIsVisible(false);
        }
    }, [open, items]);

    // Handle visibility transitions
    useEffect(() => {
        if (visible === false) {
            setIsVisible(false);
        } else if (visible === true && open) {
            setIsVisible(true);
        }
    }, [visible, open]);

    // Calculate paginated items
    const allItems = items || [];
    const totalPages = Math.ceil(allItems.length / RADIAL_PAGE_ITEMS);
    const needsPagination = allItems.length > RADIAL_PAGE_ITEMS;
    
    let displayItems = allItems;
    if (needsPagination) {
        const startIdx = (page - 1) * (RADIAL_PAGE_ITEMS - 1);
        displayItems = allItems.slice(startIdx, startIdx + RADIAL_PAGE_ITEMS - 1);
        // Add "more" item at the end
        displayItems = [...displayItems, { id: '__more__', label: 'More', icon: '...' }];
    }

    const itemCount = Math.max(displayItems.length, 3); // Minimum 3 sectors for visual balance
    const angleStep = 360 / itemCount;

    const activateItem = useCallback((index) => {
        const item = displayItems[index];
        if (!item) return;

        if (item.id === '__more__') {
            setPage(p => p < totalPages ? p + 1 : 1);
            return;
        }

        const sourceIndex = allItems.findIndex(candidate => candidate.id === item.id);
        if (sourceIndex >= 0) nuiPost('radialClick', { index: sourceIndex });
    }, [displayItems, totalPages, allItems]);

    // Handle mouse movement
    const handleMouseMove = useCallback((e) => {
        const hit = getRadialPointer(
            e.clientX,
            e.clientY,
            radialSvgRef.current,
            itemCount,
            displayItems.length
        );
        setHoverIndex(hit.type === 'item' ? hit.index : -1);
    }, [displayItems.length, itemCount]);

    // Handle click
    const handleClick = useCallback((e) => {
        const hit = getRadialPointer(
            e.clientX,
            e.clientY,
            radialSvgRef.current,
            itemCount,
            displayItems.length
        );

        if (hit.type === 'center') {
            if (page > 1) {
                setPage(p => p - 1);
            } else if (canGoBack) {
                nuiPost('radialBack', {});
            } else {
                nuiPost('radialClose', {});
            }
            return;
        }

        if (hit.type === 'item') activateItem(hit.index);
    }, [activateItem, canGoBack, displayItems.length, itemCount, page]);

    // Right-click = back/close
    const handleContextMenu = useCallback((e) => {
        e.preventDefault();
        if (page > 1) {
            setPage(p => p - 1);
        } else if (canGoBack) {
            nuiPost('radialBack', {});
        } else {
            nuiPost('radialClose', {});
        }
    }, [canGoBack, page]);

    // Keyboard handling
    useEffect(() => {
        if (!open) return;

        const handleKeyDown = (e) => {
            if (e.key === 'Escape') {
                e.preventDefault();
                nuiPost('radialClose', {});
            } else if (e.key === 'Backspace') {
                e.preventDefault();
                if (page > 1) {
                    setPage(p => p - 1);
                } else if (canGoBack) {
                    nuiPost('radialBack', {});
                }
            } else if (e.key === 'ArrowRight' || e.key === 'ArrowDown') {
                e.preventDefault();
                setHoverIndex(current => current < 0 ? 0 : (current + 1) % displayItems.length);
            } else if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') {
                e.preventDefault();
                setHoverIndex(current => current < 0 ? displayItems.length - 1
                    : (current - 1 + displayItems.length) % displayItems.length);
            } else if ((e.key === 'Enter' || e.key === ' ') && hoverIndex >= 0) {
                e.preventDefault();
                activateItem(hoverIndex);
            }
        };

        window.addEventListener('keydown', handleKeyDown);
        return () => window.removeEventListener('keydown', handleKeyDown);
    }, [activateItem, open, canGoBack, displayItems.length, hoverIndex, page]);

    if (!open) return null;

    const hoveredItem = hoverIndex >= 0 ? displayItems[hoverIndex] : null;
    const centerIcon = hoveredItem?.icon || (page > 1 ? '←' : (canGoBack ? '←' : '✕'));
    const centerLabel = hoveredItem?.label || (page > 1 ? 'Back' : (canGoBack ? 'Back' : 'Close'));

    const compactControl = appearance === 'compact-control';

    return React.createElement('div', {
        className: `es-radial-overlay${isVisible ? ' visible' : ''}${compactControl ? ' es-radial-overlay--compact-control' : ''}`,
        onMouseMove: handleMouseMove,
        onClick: handleClick,
        onContextMenu: handleContextMenu,
        'aria-label': 'Radial controls'
    },
        React.createElement('svg', {
            className: `es-radial-svg${compactControl ? ' es-radial-svg--compact-control' : ''}`,
            viewBox: `0 0 ${RADIAL_SIZE} ${RADIAL_SIZE}`,
            xmlns: 'http://www.w3.org/2000/svg',
            ref: radialSvgRef,
            role: 'menu',
            'aria-label': id ? `${id.replaceAll('_', ' ')} menu` : 'Controls menu'
        },
            // Sectors
            displayItems.map((item, i) => {
                const startAngle = i * angleStep;
                const endAngle = startAngle + angleStep;
                const isHovered = i === hoverIndex;
                const midAngle = startAngle + angleStep / 2;
                
                // Icon position
                const iconPos = polarToCartesian(RADIAL_CENTER, RADIAL_CENTER, RADIAL_ICON_RADIUS, midAngle);

                return React.createElement('g', {
                    key: item.id || i,
                    className: `es-radial-sector${isHovered ? ' hover' : ''}`,
                    role: 'menuitem',
                    'aria-label': item.label || item.id || `Item ${i + 1}`
                },
                    // Sector path
                    React.createElement('path', {
                        d: describeSector(
                            RADIAL_CENTER, RADIAL_CENTER,
                            RADIAL_OUTER_RADIUS, RADIAL_INNER_RADIUS,
                            startAngle, endAngle, RADIAL_GAP
                        ),
                        className: 'es-radial-sector-bg'
                    }),
                    // Icon
                    React.createElement('text', {
                        x: iconPos.x,
                        y: iconPos.y - 6,
                        className: 'es-radial-sector-icon',
                        textAnchor: 'middle',
                        dominantBaseline: 'middle'
                    }, item.icon || '•'),
                    // Label
                    React.createElement('text', {
                        x: iconPos.x,
                        y: iconPos.y + 14,
                        className: 'es-radial-sector-label',
                        textAnchor: 'middle',
                        dominantBaseline: 'middle'
                    }, item.label?.length > 12 ? item.label.substring(0, 11) + '...' : item.label)
                );
            }),

            // Center circle background
            React.createElement('circle', {
                cx: RADIAL_CENTER,
                cy: RADIAL_CENTER,
                r: RADIAL_INNER_RADIUS - 2,
                className: 'es-radial-center-bg'
            }),

            // Center icon
            React.createElement('text', {
                x: RADIAL_CENTER,
                y: RADIAL_CENTER - 6,
                className: 'es-radial-center-icon',
                textAnchor: 'middle',
                dominantBaseline: 'middle'
            }, centerIcon),

            // Center label  
            React.createElement('text', {
                x: RADIAL_CENTER,
                y: RADIAL_CENTER + 12,
                className: 'es-radial-center-label',
                textAnchor: 'middle',
                dominantBaseline: 'middle'
            }, centerLabel?.length > 10 ? centerLabel.substring(0, 9) + '...' : centerLabel),

            // Page indicator (if paginated)
            needsPagination && React.createElement('text', {
                x: RADIAL_CENTER,
                y: RADIAL_SIZE - 15,
                className: 'es-radial-page-indicator',
                textAnchor: 'middle'
            }, `${page}/${totalPages}`)
        )
    );
}

// ============================================================================
// SETTINGS PANEL
// ============================================================================

function SettingsField({ field, value, tabId, onChange, onAction }) {
    if (!field || typeof field !== 'object') return null;
    if (!field.type || !field.key) return null;

    const renderControl = () => {
        switch (field.type) {
            case 'toggle':
                return React.createElement('button', {
                    className: `es-settings-toggle${value ? ' on' : ''}`,
                    onClick: () => onChange(tabId, field.key, !value),
                    type: 'button',
                    role: 'switch',
                    'aria-checked': Boolean(value),
                    'aria-label': field.label
                },
                    React.createElement('span', { className: 'es-settings-toggle-knob' })
                );

            case 'select':
            case 'color':
                return React.createElement('div', { className: 'es-settings-select-wrap' },
                    React.createElement('select', {
                        className: 'es-settings-select',
                        value: value || '',
                        onChange: (e) => onChange(tabId, field.key, e.target.value)
                    },
                        (field.options || []).map(opt =>
                            React.createElement('option', { key: opt.value, value: opt.value }, opt.label)
                        )
                    ),
                    React.createElement('span', { className: 'es-settings-select-arrow' }, '▼')
                );

            case 'slider': {
                const sliderVal = value !== undefined && value !== null ? value : (field.min || 0);
                const suffix = field.suffix || '%';
                return React.createElement('div', { className: 'es-settings-slider-wrap' },
                    React.createElement('input', {
                        type: 'range',
                        className: 'es-settings-slider',
                        min: field.min !== undefined ? field.min : 0,
                        max: field.max !== undefined ? field.max : 100,
                        step: field.step !== undefined ? field.step : 1,
                        value: sliderVal,
                        onChange: (e) => onChange(tabId, field.key, Number(e.target.value))
                    }),
                    React.createElement('span', { className: 'es-settings-slider-val' }, `${sliderVal}${suffix}`)
                );
            }

            case 'buttons':
                return React.createElement('div', { className: 'es-settings-btns' },
                    (field.buttons || []).map(btn =>
                        React.createElement('button', {
                            key: btn.value,
                            type: 'button',
                            className: 'es-settings-action-btn',
                            onClick: () => onAction(tabId, field.key, btn.value)
                        }, btn.label)
                    )
                );

            case 'text':
            case 'input':
                return React.createElement('input', {
                    type: field.inputType || 'text',
                    className: 'es-settings-input',
                    placeholder: field.placeholder || '',
                    maxLength: field.maxLength,
                    spellCheck: false,
                    autoCapitalize: 'off',
                    autoCorrect: 'off',
                    value: value !== undefined && value !== null ? value : '',
                    onChange: (e) => onChange(tabId, field.key, e.target.value)
                });

            case 'soundList':
                return React.createElement('div', { className: 'es-settings-soundlist' },
                    (field.options || []).map((opt) =>
                        React.createElement('div', {
                            key: opt.value,
                            className: `es-settings-sound-item${value === opt.value ? ' selected' : ''}`
                        },
                            React.createElement('button', {
                                type: 'button',
                                className: 'es-settings-sound-select',
                                onClick: () => onChange(tabId, field.key, opt.value)
                            },
                                React.createElement('span', { className: 'es-settings-sound-radio' }),
                                React.createElement('span', { className: 'es-settings-sound-label' }, opt.label)
                            ),
                            React.createElement('button', {
                                type: 'button',
                                className: 'es-settings-sound-preview',
                                title: 'Preview',
                                onClick: (e) => {
                                    e.stopPropagation();
                                    nuiPost('settingsPreviewSound', { name: opt.name, set: opt.set });
                                }
                            }, '▶')
                        )
                    )
                );

            default:
                return null;
        }
    };

    const rowClass = field.type === 'soundList' ? 'es-settings-row es-settings-row--stack' : 'es-settings-row';

    return React.createElement('div', { className: rowClass },
        React.createElement('div', { className: 'es-settings-row-info' },
            React.createElement('div', { className: 'es-settings-row-label' }, field.label),
            field.description
                ? React.createElement('div', { className: 'es-settings-row-desc' }, field.description)
                : null
        ),
        React.createElement('div', { className: 'es-settings-row-ctrl' }, renderControl())
    );
}

function SettingsPanel({ open, tabs, onClose }) {
    const [activeTab, setActiveTab] = useState(0);
    const [values, setValues] = useState({});
    const [submitError, setSubmitError] = useState('');

    useEffect(() => {
        if (!open) return;
        nuiPost('settingsReady', {});
    }, [open]);

    useEffect(() => {
        if (!open || !tabs) return;
        const init = {};
        for (const tab of tabs) {
            if (!tab || tab.id == null) continue;
            init[tab.id] = Object.assign({}, tab.values || {});
        }
        setValues(init);
        setActiveTab(0);
        setSubmitError('');
    }, [open, tabs]);

    useEffect(() => {
        if (!open || !tabs || tabs.length === 0) return;
        if (activeTab >= tabs.length) setActiveTab(0);
    }, [open, tabs, activeTab]);

    const handleChange = useCallback((tabId, key, value) => {
        setSubmitError('');
        setValues(prev => ({
            ...prev,
            [tabId]: Object.assign({}, prev[tabId] || {}, { [key]: value })
        }));
        nuiPost('settingsPreview', { tabId, key, value });
    }, []);

    const handleReset = useCallback(() => {
        if (!tabs) return;
        const tab = tabs[activeTab];
        if (!tab) return;
        const nextValues = Object.assign({}, tab.defaults || {});
        setValues(prev => ({
            ...prev,
            [tab.id]: nextValues
        }));
        nuiPost('settingsPreview', { tabId: tab.id, values: nextValues });
    }, [tabs, activeTab]);

    const handleSave = useCallback(async () => {
        const response = await nuiPost('settingsSave', { tabs: values });
        if (response?.ok === true) {
            onClose();
            return;
        }
        setSubmitError('SAVE FAILED');
    }, [values, onClose]);

    const handleCancel = useCallback(async () => {
        const response = await nuiPost('settingsCancel', {});
        if (response?.ok === true) {
            onClose();
            return;
        }
        setSubmitError('CLOSE FAILED');
    }, [onClose]);

    const handleAction = useCallback((tabId, key, value) => {
        nuiPost('settingsAction', { tabId, key, value });
    }, []);

    useEffect(() => {
        if (!open) return;
        const onKey = (e) => { if (e.key === 'Escape') handleCancel(); };
        window.addEventListener('keydown', onKey);
        return () => window.removeEventListener('keydown', onKey);
    }, [open, handleCancel]);

    if (!open || !tabs || tabs.length === 0) return null;

    const tab = tabs[activeTab] || tabs[0];
    const tabValues = values[tab.id] || {};
    const fields = tab.fields || [];

    // Build rows with optional section headers
    const rows = [];
    let lastSection = null;
    for (let fi = 0; fi < fields.length; fi++) {
        const field = fields[fi];
        if (!field || typeof field !== 'object') continue;
        const rowKey = field.key != null && field.key !== '' ? String(field.key) : `field-${fi}`;
        if (field.section && field.section !== lastSection) {
            lastSection = field.section;
            rows.push(
                React.createElement('div', { key: `sec-${field.section}`, className: 'es-settings-section' }, field.section)
            );
        }
        rows.push(
            React.createElement(SettingsField, {
                key: rowKey,
                field,
                value: tabValues[field.key],
                tabId: tab.id,
                onChange: handleChange,
                onAction: handleAction
            })
        );
    }

    return React.createElement('div', { className: 'es-settings-overlay' },
        React.createElement('div', {
            className: 'es-settings-panel',
            role: 'dialog',
            'aria-modal': true,
            'aria-label': 'Cortex Settings'
        },
            // Header
            React.createElement('div', { className: 'es-settings-header' },
                React.createElement('div', { className: 'es-settings-title' },
                    React.createElement('span', { className: 'es-settings-accent' }, 'Cortex'),
                    ' Settings'
                ),
                React.createElement('button', {
                    type: 'button',
                    className: 'es-settings-close',
                    onClick: handleCancel,
                    'aria-label': 'Close settings and discard changes'
                }, '✕')
            ),
            // Tabs
            React.createElement('div', { className: 'es-settings-tabs', role: 'tablist', 'aria-label': 'Cortex resources' },
                tabs.map((t, i) =>
                    React.createElement('button', {
                        key: t && t.id != null ? String(t.id) : `tab-${i}`,
                        type: 'button',
                        role: 'tab',
                        'aria-selected': i === activeTab,
                        className: `es-settings-tab${i === activeTab ? ' active' : ''}`,
                        onClick: () => setActiveTab(i)
                    }, t && t.label != null ? t.label : '')
                )
            ),
            // Content
            React.createElement('div', { className: 'es-settings-content', role: 'tabpanel' }, ...rows),
            // Footer
            React.createElement('div', { className: 'es-settings-footer' },
                React.createElement('div', { className: 'es-settings-footer-left' },
                    React.createElement('button', { type: 'button', className: 'es-settings-btn reset', onClick: handleReset }, 'RESET'),
                    React.createElement(
                        'span',
                        { className: `es-settings-live-note${submitError ? ' error' : ''}` },
                        submitError || 'LIVE · SAVE TO KEEP'
                    )
                ),
                React.createElement('div', { className: 'es-settings-footer-right' },
                    React.createElement('button', { type: 'button', className: 'es-settings-btn cancel', onClick: handleCancel }, 'CANCEL'),
                    React.createElement('button', { type: 'button', className: 'es-settings-btn save', onClick: handleSave }, 'SAVE')
                )
            )
        )
    );
}

// ============================================================================
// MAIN APP
// ============================================================================

let notifyIdCounter = 0;
const INTERACTION_UI_SCALE = 0.8;
const VEHICLE_ACCESS_ACTIONS = Object.freeze({
    'vehicle-clone-key': { order: 0, icon: 'clone-key' },
    'vehicle-smash-window': { order: 1, icon: 'smash-window' }
});

function clampInteractionNumber(value, minimum, maximum) {
    return Math.max(minimum, Math.min(maximum, Number(value) || 0));
}

function getVehicleAccessPresentation(item) {
    if (item?.owner !== 'cortex-hud') return null;
    return VEHICLE_ACCESS_ACTIONS[item.id] || null;
}

function VehicleAccessIcon({ type }) {
    if (type === 'clone-key') {
        return React.createElement('svg', {
            viewBox: '0 0 20 20',
            focusable: 'false',
            'aria-hidden': 'true'
        },
            React.createElement('circle', {
                cx: '4',
                cy: '10',
                r: '1.65',
                fill: 'currentColor',
                stroke: 'none'
            }),
            React.createElement('path', { d: 'M7 6.8a4.55 4.55 0 0 1 0 6.4' }),
            React.createElement('path', { d: 'M9.5 4.3a8.1 8.1 0 0 1 0 11.4' })
        );
    }

    return React.createElement('svg', {
        viewBox: '0 0 20 20',
        focusable: 'false',
        'aria-hidden': 'true'
    },
        React.createElement('path', { d: 'M10 2.4 16 4.9v4.35c0 3.85-2.25 6.65-6 8.35-3.75-1.7-6-4.5-6-8.35V4.9L10 2.4Z' }),
        React.createElement('path', { d: 'm7.5 7.45 5 5m0-5-5 5' })
    );
}

function InteractionPrompts({ items, layout }) {
    if (!Array.isArray(items) || items.length === 0) return null;

    const screenWidth = Number(layout?.screenWidth) || 1920;
    const screenHeight = Number(layout?.screenHeight) || 1080;
    const scale = clampInteractionNumber(Math.min(screenWidth / 1920, screenHeight / 1080), 0.75, 1.5)
        * INTERACTION_UI_SCALE;
    const style = {
        '--cortex-interaction-safe-right': `${Math.max(0, Number(layout?.insetRight) || 0)}px`,
        '--cortex-interaction-safe-bottom': `${Math.max(0, Number(layout?.insetBottom) || 0)}px`,
        '--cortex-interaction-scale': scale
    };

    return React.createElement('div', {
        className: 'cortex-interactions',
        style,
        role: 'list',
        'aria-label': 'Available actions'
    }, items.map((item) => React.createElement('div', {
        className: 'cortex-interaction',
        key: `${item.owner}:${item.id}`,
        role: 'listitem'
    },
        React.createElement('span', { className: 'cortex-interaction-label' }, item.label),
        React.createElement('span', {
            className: `cortex-interaction-key${item.key.length > 3 ? ' is-wide' : ''}`,
            'aria-label': `Press ${item.key}`
        }, item.key)
    )));
}

function WorldInteractionPrompts({ items }) {
    if (!Array.isArray(items) || items.length === 0) return null;

    const vehicleAccessItems = items
        .filter((item) => getVehicleAccessPresentation(item))
        .sort((left, right) => (
            getVehicleAccessPresentation(left).order - getVehicleAccessPresentation(right).order
        ));
    const standardItems = items.filter((item) => !getVehicleAccessPresentation(item));
    const prompts = standardItems.map((item) => {
        const scale = clampInteractionNumber(1.035 - (item.distance * 0.025), 0.96, 1.02)
            * INTERACTION_UI_SCALE;
        const style = {
            '--cortex-world-x': `${clampInteractionNumber(item.x, 0, 1) * 100}vw`,
            '--cortex-world-y': `${clampInteractionNumber(item.y, 0, 1) * 100}vh`,
            '--cortex-world-scale': scale
        };

        return React.createElement('div', {
            className: 'cortex-world-interaction',
            key: `${item.owner}:${item.id}`,
            style,
            role: 'listitem'
        },
            React.createElement('span', { className: 'cortex-world-interaction-label' }, item.label),
            React.createElement('span', {
                className: `cortex-world-interaction-key${item.key.length > 3 ? ' is-wide' : ''}`,
                'aria-label': `Use the action button to ${item.label.toLowerCase()}`
            }, item.key)
        );
    });

    if (vehicleAccessItems.length > 0) {
        const itemCount = vehicleAccessItems.length;
        const anchor = vehicleAccessItems.reduce((position, item) => ({
            x: position.x + clampInteractionNumber(item.x, 0, 1) / itemCount,
            y: position.y + clampInteractionNumber(item.y, 0, 1) / itemCount,
            distance: position.distance + Math.max(0, Number(item.distance) || 0) / itemCount
        }), { x: 0, y: 0, distance: 0 });
        const scale = clampInteractionNumber(1.035 - (anchor.distance * 0.025), 0.96, 1.02)
            * INTERACTION_UI_SCALE;
        const style = {
            '--cortex-world-x': `${anchor.x * 100}vw`,
            '--cortex-world-y': `${anchor.y * 100}vh`,
            '--cortex-world-scale': scale,
            '--cortex-access-shift-x': anchor.x < 0.22 ? '0%' : (anchor.x > 0.78 ? '-100%' : '-50%'),
            '--cortex-access-shift-y': anchor.y < 0.12 ? '0%' : (anchor.y > 0.88 ? '-100%' : '-50%')
        };

        prompts.push(React.createElement('div', {
            className: 'cortex-world-access',
            key: 'cortex-hud:vehicle-access',
            style,
            role: 'presentation'
        }, vehicleAccessItems.map((item) => {
            const presentation = getVehicleAccessPresentation(item);
            const actionName = String(item.label || '').toLowerCase();

            return React.createElement('div', {
                className: `cortex-world-access-row is-${presentation.icon}`,
                key: `${item.owner}:${item.id}`,
                role: 'listitem'
            },
                React.createElement('span', {
                    className: `cortex-world-access-key${item.key.length > 3 ? ' is-wide' : ''}`,
                    'aria-label': `Press ${item.key} to ${actionName}`
                }, item.key),
                React.createElement('span', {
                    className: 'cortex-world-access-icon',
                    'aria-hidden': 'true'
                }, React.createElement(VehicleAccessIcon, { type: presentation.icon })),
                React.createElement('span', { className: 'cortex-world-access-label' }, item.label)
            );
        })));
    }

    return React.createElement('div', {
        className: 'cortex-world-interactions',
        role: 'list',
        'aria-label': 'Nearby world actions'
    }, prompts);
}

function App() {
    const [notifications, setNotifications] = useState([]);
    const [notifyPosition, setNotifyPosition] = useState('top-right');
    const [progress, setProgress] = useState({
        active: false,
        duration: 0,
        label: '',
        position: 'bottom',
        style: 'bar',
        canCancel: false
    });

    const [debugPanel, setDebugPanel] = useState({
        open: false,
        title: '',
        subtitle: '',
        position: 'top-right',
        accentColor: null,
        lines: [],
        data: null
    });

    const [alertDialog, setAlertDialog] = useState({
        open: false,
        header: '',
        content: '',
        centered: false,
        cancel: true,
        labels: { confirm: 'CONFIRM', cancel: 'CANCEL' },
        style: null
    });

    const [textUi, setTextUi] = useState({
        open: false,
        text: '',
        position: 'bottom-center',
        icon: null,
        style: null,
        backdrop: false
    });

    const [menu, setMenu] = useState({
        open: false,
        id: null,
        title: '',
        subtitle: '',
        position: 'top-left',
        canClose: true,
        disableInput: false,
        options: [],
        selected: 1,
        tooltip: ''
    });

    const [help, setHelp] = useState({
        open: false,
        items: []
    });

    const [radial, setRadial] = useState({
        open: false,
        id: null,
        items: [],
        canGoBack: false,
        visible: true,
        appearance: null
    });

    const [contextMenu, setContextMenu] = useState({
        open: false,
        title: '',
        fields: [],
        values: {},
        labels: { confirm: 'CONFIRM', cancel: 'CANCEL' }
    });

    const [uiApps, setUiApps] = useState({});

    const [settingsPanel, setSettingsPanel] = useState({ open: false, tabs: [] });

    const [interactionItems, setInteractionItems] = useState([]);
    const [worldInteractionItems, setWorldInteractionItems] = useState([]);
    const [interactionLayout, setInteractionLayout] = useState({
        insetRight: 0,
        insetBottom: 0,
        screenWidth: 1920,
        screenHeight: 1080
    });

    useEffect(() => {
        if (typeof GetParentResourceName !== 'function') return;

        fetch(`https://${GetParentResourceName()}/interactionReady`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: '{}'
        }).catch(() => {});
    }, []);

    const closeSettingsPanelLocal = useCallback(() => {
        setSettingsPanel(prev => ({ ...prev, open: false }));
    }, []);

    const removeNotification = useCallback((id) => {
        setNotifications(prev => prev.filter(n => n.id !== id));
    }, []);

    const addNotification = useCallback((data) => {
        const duration = data.duration ?? 3000;
        const persistent = data.persistent || duration === 0;

        if (data.position) {
            setNotifyPosition(data.position);
        }

        const typeNorm = data.type || 'info';
        const titleNorm = data.title == null ? '' : String(data.title);
        const descNorm = data.description == null ? '' : String(data.description);
        const dedupeKey = `${typeNorm}\u0000${titleNorm}\u0000${descNorm}`;
        const allowDedupe = data.dedupe !== false;
        const visualOptions = {
            plain: Boolean(data.plain),
            hideIcon: data.hideIcon === true || data.icon === false
        };

        setNotifications(prev => {
            if (data.id) {
                const id = data.id;
                const notification = {
                    id,
                    dedupeKey,
                    type: typeNorm,
                    title: data.title,
                    description: data.description,
                    duration,
                    showDuration: data.showDuration,
                    persistent,
                    ...visualOptions
                };
                const without = prev.filter(n => n.id !== id);
                return [...without, notification];
            }

            if (allowDedupe) {
                const dupIdx = prev.findIndex(n => n.dedupeKey === dedupeKey);
                if (dupIdx !== -1) {
                    const next = prev.slice();
                    const kept = next[dupIdx];
                    next[dupIdx] = {
                        ...kept,
                        refreshTick: (kept.refreshTick || 0) + 1,
                        type: typeNorm,
                        title: data.title,
                        description: data.description,
                        duration,
                        showDuration: data.showDuration,
                        persistent,
                        ...visualOptions
                    };
                    return next;
                }
            }

            const id = `notify-${++notifyIdCounter}`;
            const notification = {
                id,
                dedupeKey,
                type: typeNorm,
                title: data.title,
                description: data.description,
                duration,
                showDuration: data.showDuration,
                persistent,
                ...visualOptions
            };
            return [...prev, notification];
        });
    }, []);

    const clearNotifications = useCallback(() => {
        setNotifications([]);
    }, []);

    const startProgress = useCallback((data) => {
        setProgress({
            active: true,
            duration: data.duration || 0,
            label: data.label || '',
            position: data.position || 'bottom',
            style: data.style || 'bar',
            canCancel: data.canCancel || false
        });
    }, []);

    const endProgress = useCallback(() => {
        setProgress(prev => ({ ...prev, active: false }));
    }, []);

    const closeAlertDialog = useCallback(async (result) => {
        setAlertDialog(prev => ({ ...prev, open: false }));

        try {
            await fetch(`https://${GetParentResourceName()}/alertDialogResult`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify({ result })
            });
        } catch (e) {
            uiDebugLog('alertDialogResult post failed', e);
        }
    }, []);

    const closeContextMenu = useCallback(async (result, values) => {
        setContextMenu(prev => ({ ...prev, open: false }));

        try {
            await fetch(`https://${GetParentResourceName()}/contextMenuResult`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify({ result, values })
            });
        } catch (e) {
            uiDebugLog('contextMenuResult post failed', e);
        }
    }, []);

    const openMenu = useCallback((data) => {
        const normalizedOptions = Array.isArray(data?.options)
            ? data.options.map(normalizeOption)
            : [];

        const initialSelected = normalizedOptions.length ? 1 : 0;
        const tooltip = normalizedOptions.length ? (normalizedOptions[0].description || '') : '';

        setMenu({
            open: true,
            id: data?.id || null,
            title: data?.title || '',
            subtitle: data?.subtitle || '',
            position: data?.position || 'top-left',
            canClose: data?.canClose !== false,
            disableInput: Boolean(data?.disableInput),
            options: normalizedOptions,
            selected: initialSelected,
            tooltip
        });
    }, [setMenu]);

    const closeMenuLocal = useCallback(() => {
        setMenu(prev => ({ ...prev, open: false, id: null }));
    }, [setMenu]);

    const setMenuOptionsAll = useCallback((data) => {
        setMenu(prev => {
            if (!prev.open || prev.id !== data?.id) return prev;
            const normalizedOptions = Array.isArray(data?.options)
                ? data.options.map(normalizeOption)
                : [];
            const selectedIndex = normalizedOptions.length
                ? Math.max(1, Math.min(prev.selected || 1, normalizedOptions.length))
                : 0;
            const tooltip = normalizedOptions.length
                ? (normalizedOptions[selectedIndex - 1]?.description || '')
                : '';
            return { ...prev, options: normalizedOptions, selected: selectedIndex, tooltip };
        });
    }, [setMenu]);

    const setMenuOptionSingle = useCallback((data) => {
        setMenu(prev => {
            if (!prev.open || prev.id !== data?.id) return prev;
            const index = data?.index;
            if (typeof index !== 'number' || index < 1) return prev;

            const next = prev.options.slice(0);
            next[index - 1] = normalizeOption(data?.option || {});

            const tooltip = next.length
                ? (next[(prev.selected || 1) - 1]?.description || '')
                : '';

            return { ...prev, options: next, tooltip };
        });
    }, [setMenu]);

    // NUI message handler
    useEffect(() => {
        const handleMessage = (event) => {
            const { action, data } = event.data;

            if (uiDebugEnabled) {
                uiDebugLog('message', action, safeJson(data));
            }

            switch (action) {
                case 'debugPing':
                    addNotification({
                        type: 'info',
                        title: 'UI Debug',
                        description: `Ping OK: ${new Date().toLocaleTimeString()}`,
                        duration: 1500,
                        showDuration: true,
                        position: data?.position || 'top-right'
                    });
                    break;
                case 'debugState':
                    addNotification({
                        type: 'info',
                        title: 'UI Debug',
                        description: `notifications=${notifications.length} position=${notifyPosition}`,
                        duration: 2500,
                        showDuration: true,
                        position: notifyPosition
                    });
                    break;
                case 'notify':
                    addNotification(data);
                    break;
                case 'menuOpen':
                    openMenu(data);
                    break;
                case 'menuClose':
                    closeMenuLocal();
                    break;
                case 'menuSetOptions':
                    setMenuOptionsAll(data);
                    break;
                case 'menuSetOption':
                    setMenuOptionSingle(data);
                    break;
                case 'uiAppOpen':
                    setUiApps(prev => ({
                        ...prev,
                        [data?.id]: { open: true, payload: data?.payload || {} }
                    }));
                    break;
                case 'uiAppData':
                    setUiApps(prev => ({
                        ...prev,
                        [data?.id]: { ...(prev[data?.id] || {}), payload: { ...(prev[data?.id]?.payload || {}), ...(data?.payload || {}) } }
                    }));
                    break;
                case 'uiAppClose':
                    setUiApps(prev => ({
                        ...prev,
                        [data?.id]: { ...(prev[data?.id] || {}), open: false }
                    }));
                    break;
                case 'debugPanelShow':
                    setDebugPanel({
                        open: true,
                        title: data?.title || 'DEBUG',
                        subtitle: data?.subtitle || '',
                        position: data?.position || 'top-right',
                        accentColor: data?.accentColor || null,
                        lines: Array.isArray(data?.lines) ? data.lines : [],
                        data: data?.data || null
                    });
                    break;
                case 'debugPanelUpdate':
                    setDebugPanel(prev => ({
                        ...prev,
                        title: data?.title ?? prev.title,
                        subtitle: data?.subtitle ?? prev.subtitle,
                        position: data?.position ?? prev.position,
                        accentColor: data?.accentColor ?? prev.accentColor,
                        lines: Array.isArray(data?.lines) ? data.lines : prev.lines,
                        data: data?.data ?? prev.data
                    }));
                    break;
                case 'debugPanelHide':
                    setDebugPanel(prev => ({ ...prev, open: false }));
                    break;
                case 'hideNotify':
                    if (data?.id) {
                        removeNotification(data.id);
                    }
                    break;
                case 'clearNotifications':
                    clearNotifications();
                    break;
                case 'progressStart':
                    startProgress(data);
                    break;
                case 'progressEnd':
                    endProgress();
                    break;
                case 'alertDialog': {
                    const content = Array.isArray(data?.content) ? data.content.join('\n') : (data?.content || '');
                    setAlertDialog({
                        open: true,
                        header: data?.header || '',
                        content,
                        centered: Boolean(data?.centered),
                        cancel: data?.cancel !== false,
                        labels: {
                            confirm: data?.labels?.confirm || 'CONFIRM',
                            cancel: data?.labels?.cancel || 'CANCEL'
                        },
                        style: data?.style || null
                    });
                    break;
                }
                case 'contextMenu': {
                    setContextMenu({
                        open: true,
                        title: data?.title || '',
                        fields: Array.isArray(data?.fields) ? data.fields : [],
                        values: data?.values || {},
                        labels: {
                            confirm: data?.labels?.confirm || 'CONFIRM',
                            cancel: data?.labels?.cancel || 'CANCEL'
                        }
                    });
                    break;
                }
                case 'contextMenuClose':
                    setContextMenu(prev => ({ ...prev, open: false }));
                    break;
                case 'textUIShow': {
                    setTextUi({
                        open: true,
                        text: data?.text || '',
                        position: data?.position || 'bottom-center',
                        icon: data?.icon || null,
                        style: data?.style || null,
                        backdrop: Boolean(data?.backdrop)
                    });
                    break;
                }
                case 'textUIHide':
                    setTextUi(prev => ({ ...prev, open: false }));
                    break;
                case 'helpShow':
                    setHelp({ open: true, items: data.items || [] });
                    break;
                case 'helpHide':
                    setHelp(prev => ({ ...prev, open: false }));
                    break;
                case 'radialShow':
                    setRadial({
                        open: true,
                        id: data?.menuId || null,
                        items: Array.isArray(data?.items) ? data.items : [],
                        canGoBack: Boolean(data?.canGoBack),
                        appearance: data?.appearance || null,
                        visible: true
                    });
                    break;
                case 'radialHide':
                    setRadial(prev => ({ ...prev, open: false, visible: false }));
                    break;
                case 'radialRefresh':
                    setRadial(prev => ({
                        ...prev,
                        id: data?.menuId || prev.id,
                        items: Array.isArray(data?.items) ? data.items : prev.items,
                        canGoBack: data?.canGoBack !== undefined ? Boolean(data.canGoBack) : prev.canGoBack,
                        appearance: data?.appearance !== undefined ? data.appearance : prev.appearance
                    }));
                    break;
                case 'radialTransitionOut':
                    setRadial(prev => ({ ...prev, visible: false }));
                    break;
                case 'radialTransitionIn':
                    setRadial(prev => ({
                        ...prev,
                        id: data?.menuId || null,
                        items: Array.isArray(data?.items) ? data.items : [],
                        canGoBack: Boolean(data?.canGoBack),
                        appearance: data?.appearance || null,
                        visible: true
                    }));
                    break;
                case 'settingsOpen':
                    setSettingsPanel({ open: true, tabs: Array.isArray(data?.tabs) ? data.tabs : [] });
                    break;
                case 'settingsClose':
                    setSettingsPanel(prev => ({ ...prev, open: false }));
                    break;
                case 'notifySetPosition':
                    if (data?.position) setNotifyPosition(data.position);
                    break;
                case 'interaction:update':
                    setInteractionItems(Array.isArray(data?.items) ? data.items.slice(0, 8) : []);
                    break;
                case 'interaction:world':
                    setWorldInteractionItems(Array.isArray(data?.items)
                        ? data.items.filter((item) => item
                            && typeof item.label === 'string'
                            && typeof item.key === 'string'
                            && Number.isFinite(Number(item.x))
                            && Number.isFinite(Number(item.y)))
                            .slice(0, 4)
                            .map((item, index) => ({
                                id: typeof item.id === 'string' ? item.id : `world-${index}`,
                                owner: typeof item.owner === 'string' ? item.owner : 'unknown',
                                label: item.label.trim().slice(0, 96),
                                key: item.key.trim().slice(0, 16),
                                x: clampInteractionNumber(item.x, 0, 1),
                                y: clampInteractionNumber(item.y, 0, 1),
                                distance: clampInteractionNumber(item.distance, 0, 25)
                            }))
                        : []);
                    break;
                case 'interaction:layout':
                    setInteractionLayout(prev => ({ ...prev, ...(data || {}) }));
                    break;
            }
        };

        window.addEventListener('message', handleMessage);
        return () => window.removeEventListener('message', handleMessage);
    }, [addNotification, removeNotification, clearNotifications, startProgress, endProgress, openMenu, closeMenuLocal, setMenuOptionsAll, setMenuOptionSingle, notifications.length, notifyPosition, setDebugPanel]);

    return React.createElement(React.Fragment, null,
        React.createElement(NotificationContainer, {
            notifications,
            position: notifyPosition,
            onRemove: removeNotification
        }),
        React.createElement(ProgressBar, progress),
        React.createElement(TextUI, { ...textUi }),
        React.createElement(AlertDialog, { ...alertDialog, onClose: closeAlertDialog }),
        React.createElement(ContextMenu, { ...contextMenu, onClose: closeContextMenu }),
        React.createElement(DebugPanel, { ...debugPanel }),
        React.createElement(HelpBar, { ...help }),
        React.createElement(RadialMenu, { ...radial }),
        React.createElement(WeatherZoneEditorApp, { appState: uiApps[WEATHER_EDITOR_APP_ID], setUiApps }),
        React.createElement(Menu, { ...menu, setMenu }),
        React.createElement(SettingsPanel, { ...settingsPanel, onClose: closeSettingsPanelLocal }),
        settingsPanel.open ? null : React.createElement(InteractionPrompts, { items: interactionItems, layout: interactionLayout }),
        settingsPanel.open ? null : React.createElement(WorldInteractionPrompts, { items: worldInteractionItems })
    );
}

// ============================================================================
// DYNAMIC STYLES
// ============================================================================

// Keep only truly dynamic keyframes here; all layout styles live in style.css
const style = document.createElement('style');
style.textContent = `@keyframes shrink { from { width: 100%; } to { width: 0%; } }`;
document.head.appendChild(style);

// ============================================================================
// RENDER APP
// ============================================================================

const rootEl = document.getElementById('root');

// React 18: ReactDOM.createRoot
// React 17/legacy: ReactDOM.render
if (ReactDOM.createRoot) {
    const root = ReactDOM.createRoot(rootEl);
    root.render(React.createElement(App));
} else {
    ReactDOM.render(React.createElement(App), rootEl);
}
