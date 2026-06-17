#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Propuesta de Proyecto: Cyber Range FIEE-UNI"""

from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import cm
from reportlab.lib.colors import HexColor, white, black
from reportlab.platypus import (SimpleDocTemplate, Paragraph, Spacer, Table,
                                 TableStyle, PageBreak, HRFlowable)
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_JUSTIFY, TA_RIGHT

PAGE_W, PAGE_H = A4
MARGIN = 2.0 * cm

DARK_BLUE  = HexColor('#1a3a5c')
MID_BLUE   = HexColor('#2c5f8a')
LIGHT_BLUE = HexColor('#e8f0f7')
LIGHT_GRAY = HexColor('#f2f2f2')
MID_GRAY   = HexColor('#cccccc')
DARK_GRAY  = HexColor('#555555')
ACCENT     = HexColor('#c41e3a')
COL_W      = PAGE_W - 2 * MARGIN

def S(name, **kw):
    defaults = dict(fontName='Helvetica', fontSize=9, textColor=black,
                    spaceAfter=3, leading=13)
    defaults.update(kw)
    return ParagraphStyle(name, **defaults)

def P(text, style):
    return Paragraph(text, style)

body      = S('body', alignment=TA_JUSTIFY, leading=14, fontSize=9.5)
note      = S('note', fontName='Helvetica-Oblique', fontSize=8.5, textColor=DARK_GRAY, leading=12)
bullet    = S('bullet', leftIndent=14, firstLineIndent=-10, leading=13, fontSize=9.5, spaceAfter=2)
th        = S('th', fontName='Helvetica-Bold', fontSize=9, textColor=white, alignment=TA_CENTER, leading=12)
tc        = S('tc', fontSize=9, leading=12, spaceAfter=0)
tc_c      = S('tc_c', fontSize=9, leading=12, alignment=TA_CENTER, spaceAfter=0)
tc_b      = S('tc_b', fontName='Helvetica-Bold', fontSize=9, textColor=DARK_BLUE, leading=12, spaceAfter=0)
meta      = S('meta', textColor=DARK_GRAY, alignment=TA_CENTER, fontSize=9)
sig_label = S('sig_label', fontName='Helvetica-Bold', fontSize=9, alignment=TA_CENTER)
sig_sub   = S('sig_sub', fontSize=8.5, textColor=DARK_GRAY, alignment=TA_CENTER)
crit      = S('crit', fontName='Helvetica-Bold', fontSize=9, textColor=ACCENT, alignment=TA_CENTER)
high      = S('high', fontName='Helvetica-Bold', fontSize=9, textColor=DARK_BLUE, alignment=TA_CENTER)

def banner(text):
    data = [[P(text, S('bn', fontName='Helvetica-Bold', fontSize=9, textColor=white, alignment=TA_CENTER))]]
    t = Table(data, colWidths=[COL_W])
    t.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,-1), DARK_BLUE),
        ('LEFTPADDING', (0,0), (-1,-1), 8),
        ('TOPPADDING', (0,0), (-1,-1), 6),
        ('BOTTOMPADDING', (0,0), (-1,-1), 6),
    ]))
    return t

def section(number, title):
    label = f'{number}. {title.upper()}'
    data = [[P(label, S('sh', fontName='Helvetica-Bold', fontSize=10.5, textColor=white))]]
    t = Table(data, colWidths=[COL_W])
    t.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,-1), DARK_BLUE),
        ('LEFTPADDING', (0,0), (-1,-1), 8),
        ('TOPPADDING', (0,0), (-1,-1), 5),
        ('BOTTOMPADDING', (0,0), (-1,-1), 5),
    ]))
    return t

def tbl_style(t, row_colors=None):
    style = [
        ('BACKGROUND', (0, 0), (-1, 0), DARK_BLUE),
        ('GRID', (0, 0), (-1, -1), 0.4, MID_GRAY),
        ('LEFTPADDING', (0, 0), (-1, -1), 5),
        ('RIGHTPADDING', (0, 0), (-1, -1), 5),
        ('TOPPADDING', (0, 0), (-1, -1), 4),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
    ]
    if row_colors:
        style.append(('ROWBACKGROUNDS', (0, 1), (-1, -1), row_colors))
    else:
        style.append(('ROWBACKGROUNDS', (0, 1), (-1, -1), [LIGHT_GRAY, white]))
    return TableStyle(style)


# ── BUILD ────────────────────────────────────────────────────────────────────
output = '/home/researcher/Research/titulacion/docs/propuesta-cyber-range-alumnos.pdf'
doc = SimpleDocTemplate(output, pagesize=A4,
                        rightMargin=MARGIN, leftMargin=MARGIN,
                        topMargin=2.2*cm, bottomMargin=2.2*cm,
                        title='Propuesta Cyber Range FIEE-UNI')
story = []

# ── HEADER ───────────────────────────────────────────────────────────────────
story.append(banner('UNIVERSIDAD NACIONAL DE INGENIERIA  ·  FACULTAD DE INGENIERIA ELECTRICA Y ELECTRONICA'))
story.append(Spacer(1, 0.4*cm))
story.append(P('PROPUESTA DE PROYECTO', S('pt', fontSize=10, textColor=DARK_GRAY, alignment=TA_CENTER)))
story.append(Spacer(1, 0.15*cm))
story.append(P('Implementacion de Cyber Range para Emulacion de APT',
               S('tit', fontName='Helvetica-Bold', fontSize=15, textColor=DARK_BLUE, alignment=TA_CENTER, leading=20)))
story.append(P('en el Laboratorio de Ciberseguridad  (Laboratorio #2)  —  FIEE-UNI',
               S('sub', fontSize=10, textColor=DARK_GRAY, alignment=TA_CENTER)))
story.append(Spacer(1, 0.25*cm))
story.append(HRFlowable(width='100%', thickness=2, color=ACCENT, spaceAfter=4))
story.append(P('Especialidad de Ciberseguridad  |  Lima, junio 2026  |  Version 1.0', meta))
story.append(HRFlowable(width='100%', thickness=0.5, color=MID_GRAY, spaceAfter=8))

# ── 1. PRESENTACION ──────────────────────────────────────────────────────────
story.append(section('1', 'Presentacion'))
story.append(Spacer(1, 0.2*cm))
story.append(P(
    'El Laboratorio de Ciberseguridad de la FIEE-UNI (Laboratorio #2) dispone de infraestructura '
    'de computo de alto rendimiento instalada en los Ciber Rooms que aun no cuenta con un uso '
    'sistematico dentro del curriculo de la especialidad. Este proyecto propone activar esa '
    'infraestructura de forma inmediata como un <b>Cyber Range funcional</b>: un entorno de '
    'laboratorio completamente aislado donde los alumnos ejecutan, observan y detectan ataques '
    'reales de grupos APT (<i>Advanced Persistent Threats</i>) sin riesgo alguno para las redes '
    'de la facultad.',
    body))
story.append(Spacer(1, 0.1*cm))
story.append(P(
    'La iniciativa persigue tres objetivos de forma simultanea: dar uso productivo e inmediato '
    'a los equipos ya disponibles, incorporar a los alumnos en un proyecto de investigacion '
    'aplicada con resultado publicable, y generar un activo academico reutilizable —dataset, '
    'guias y runbooks— para futuras cohortes de la especialidad.',
    body))

# ── 2. OBJETIVO ──────────────────────────────────────────────────────────────
story.append(Spacer(1, 0.2*cm))
story.append(section('2', 'Objetivo del Proyecto'))
story.append(Spacer(1, 0.2*cm))
story.append(P('<b>Objetivo general</b>',
               S('sub2', fontName='Helvetica-Bold', fontSize=10, textColor=DARK_BLUE, spaceAfter=4)))
story.append(P(
    'Implementar un Cyber Range basado en Proxmox VE para la emulacion de ataques de tres '
    'grupos APT reales (APT29, OilRig, Wizard Spider) y su deteccion mediante Elastic Stack, '
    'integrando a los alumnos de la especialidad en un proyecto practico con resultado '
    'academico publicable.',
    body))
story.append(Spacer(1, 0.1*cm))
story.append(P('<b>Objetivos especificos</b>',
               S('sub2', fontName='Helvetica-Bold', fontSize=10, textColor=DARK_BLUE, spaceAfter=4)))
for item in [
    'Configurar Proxmox VE en los 24 servidores fisicos del Laboratorio #2.',
    'Desplegar un entorno de red aislado con SIEM (Elastic Stack), EDR (Elastic Defend) '
    'y plataforma de emulacion de adversarios (CALDERA 5.x).',
    'Ejecutar tres escenarios de emulacion APT basados en los planes CTID del MITRE '
    '(APT29 — espionaje; OilRig — webshell EWS; Wizard Spider — Ryuk ransomware).',
    'Recolectar y analizar la telemetria generada: Sysmon, Packetbeat y Windows Event Log.',
    'Publicar los resultados como dataset y guia de referencia en GitHub Pages.',
]:
    story.append(P(f'•  {item}', bullet))

# ── 3. INFRAESTRUCTURA ───────────────────────────────────────────────────────
story.append(Spacer(1, 0.2*cm))
story.append(section('3', 'Infraestructura Disponible'))
story.append(Spacer(1, 0.2*cm))
story.append(P(
    'El laboratorio dispone de <b>4 grupos de 6 servidores fisicos</b> cada uno (24 equipos en '
    'total). Cada grupo constituye una instancia independiente del Cyber Range, permitiendo que '
    '4 equipos de alumnos trabajen en paralelo.',
    body))
story.append(Spacer(1, 0.2*cm))

hw = [
    [P('Recurso', th), P('Cant.', th), P('Especificacion', th), P('Observacion', th)],
    [P('Servidores fisicos', tc_b), P('24', tc_c), P('20 vCPU · 16 GB RAM · 220 GB SSD', tc), P('6 por grupo — Proxmox VE 8.x', tc)],
    [P('Switches administrables', tc_b), P('4', tc_c), P('802.1Q VLAN, ≥8 puertos GbE', tc), P('1 por grupo — ya disponibles', tc)],
    [P('Cables de red (patch)', tc_b), P('~32', tc_c), P('Cat5e/Cat6 · 3 m', tc), P('6 maquinas/switch + 2 repuesto = 32 total', tc)],
    [P('Routers', tc_b), P('—', tc_c), P('Opcional', tc), P('No requeridos; segmentacion via VLANs 802.1Q y bridges Proxmox', tc)],
]
t = Table(hw, colWidths=[4.0*cm, 1.4*cm, 5.8*cm, 5.5*cm])
t.setStyle(tbl_style(t))
story.append(t)
story.append(Spacer(1, 0.1*cm))
story.append(P(
    '<i>Nota sobre cables: cada maquina fisica necesita 1 cable al switch del grupo (un unico '
    'cable troncal 802.1Q transporta las VLANs MGMT y TARGET). 6 cables x 4 grupos = 24 cables; '
    'se recomiendan 8 adicionales de repuesto, total 32 x 3 m.</i>',
    note))

# ── 4. ARQUITECTURA ──────────────────────────────────────────────────────────
story.append(Spacer(1, 0.2*cm))
story.append(section('4', 'Arquitectura Tecnica del Cyber Range'))
story.append(Spacer(1, 0.2*cm))
story.append(P(
    'Cada instancia de Cyber Range (un grupo de 6 servidores) despliega las '
    'siguientes maquinas virtuales sobre Proxmox VE:',
    body))
story.append(Spacer(1, 0.15*cm))

arch = [
    [P('Servidor fisico', th), P('VM(s) desplegada(s)', th), P('Sistema operativo', th), P('Funcion en el escenario', th)],
    [P('Host 1', tc_b), P('elastic-vm (14 GB RAM)', tc), P('Ubuntu 22.04 LTS', tc), P('SIEM: Elasticsearch + Kibana + Fleet Server', tc)],
    [P('Host 2', tc_b), P('dc01 (4 GB) + sql01 (5 GB)', tc), P('Windows Server 2019', tc), P('Controlador de dominio + SQL Server 2019 Developer', tc)],
    [P('Host 3', tc_b), P('exchange01 (10 GB)', tc), P('Windows Server 2019 + Exchange 2019', tc), P('Servidor de correo / objetivo EWS (escenario OilRig)', tc)],
    [P('Host 4', tc_b), P('ws01 (4 GB) + ws02 (4 GB)', tc), P('Windows 10', tc), P('Estaciones de trabajo victimas (APT29, Wizard Spider)', tc)],
    [P('Host 5', tc_b), P('SPARE / IDS futuro', tc), P('—', tc_c), P('Reservado para sensor IDS de red (Suricata/Zeek)', tc)],
    [P('Host 6', tc_b), P('caldera-vm (4 GB) + kali (4 GB)', tc), P('Ubuntu 22.04 / Kali Linux', tc), P('C2 CALDERA + plataforma de ataque red team', tc)],
]
t2 = Table(arch, colWidths=[2.5*cm, 4.3*cm, 4.2*cm, 5.7*cm])
t2.setStyle(tbl_style(t2))
story.append(t2)

# PAGE BREAK
story.append(PageBreak())

# ── 5. PLAN DE EJECUCION ─────────────────────────────────────────────────────
story.append(section('5', 'Plan de Ejecucion  —  4 Semanas'))
story.append(Spacer(1, 0.2*cm))

plan = [
    [P('Semana', th), P('Actividades principales', th), P('Entregable', th)],
    [P('<b>Semana 1</b>\nInvestigacion y\naprendizaje', tc),
     P('• Estudio de Proxmox VE, Elastic Stack y CALDERA\n'
       '• Revision de planes CTID (APT29, OilRig, Wizard Spider)\n'
       '• Configuracion de cuentas GitHub y entorno de trabajo\n'
       '• Definicion de roles dentro de cada equipo de 6', tc),
     P('Plan de setup documentado por grupo\n(arquitectura de red, asignacion de VMs)', tc)],
    [P('<b>Semana 2</b>\nImplementacion\nde servidores', tc),
     P('• Instalacion de Proxmox VE en los 6 servidores del grupo\n'
       '• Configuracion de VLANs (MGMT 10.0.0.0/24, TARGET 10.10.10.0/24)\n'
       '• Despliegue de VMs: elastic-vm, dc01, exchange01, sql01, ws01/ws02, kali\n'
       '• Instalacion de Elastic Stack, Fleet Server y Elastic Defend (modo Detect)\n'
       '• Configuracion de Sysmon (sysmon-modular) en VMs Windows\n'
       '• Validacion: todos los agentes en estado Healthy en Kibana Fleet', tc),
     P('Cyber Range operativo:\n'
       '- https://10.0.0.10:5601 accesible\n'
       '- Todos los Elastic Agents en Healthy\n'
       '- Telemetria visible en Kibana Discover', tc)],
    [P('<b>Semana 3</b>\nEmulacion de\nataques APT', tc),
     P('• Carga de adversary plans CTID en CALDERA 5.x\n'
       '• Ejecucion del escenario APT29 (espionaje rapido, 2 workstations)\n'
       '• Ejecucion del escenario OilRig (phishing → webshell EWS → exfiltracion SQL)\n'
       '• Ejecucion del escenario Wizard Spider (Emotet → TrickBot → Ryuk)\n'
       '• Captura y etiquetado de telemetria por escenario y run', tc),
     P('Dataset FullAPT-2025 generado:\n'
       '- Indices separados por escenario y run\n'
       '- Tecnicas ATT&CK ejecutadas documentadas', tc)],
    [P('<b>Semana 4</b>\nAnalisis y\npublicacion', tc),
     P('• Analisis de telemetria: correlacion de eventos y deteccion de TTPs\n'
       '• Creacion y ajuste de reglas de deteccion en Elastic SIEM\n'
       '• Evaluacion de Elastic ML (anomaly detection jobs sin datos etiquetados)\n'
       '• Redaccion del informe tecnico por grupo\n'
       '• Publicacion en GitHub Pages: guia de setup + runbooks APT\n'
       '• Presentacion final con demo en vivo del Cyber Range', tc),
     P('Informe tecnico por grupo\nGitHub Pages publicado\nDemo en vivo del Cyber Range', tc)],
]
t3 = Table(plan, colWidths=[2.8*cm, 9.0*cm, 4.9*cm])
t3.setStyle(TableStyle([
    ('BACKGROUND', (0,0), (-1,0), DARK_BLUE),
    ('ROWBACKGROUNDS', (0,1), (-1,-1), [LIGHT_BLUE, white]),
    ('GRID', (0,0), (-1,-1), 0.4, MID_GRAY),
    ('LEFTPADDING', (0,0), (-1,-1), 5),
    ('RIGHTPADDING', (0,0), (-1,-1), 5),
    ('TOPPADDING', (0,0), (-1,-1), 5),
    ('BOTTOMPADDING', (0,0), (-1,-1), 5),
    ('VALIGN', (0,0), (-1,-1), 'TOP'),
    ('FONTNAME', (0,1), (0,-1), 'Helvetica-Bold'),
    ('FONTSIZE', (0,1), (0,-1), 9),
]))
story.append(t3)

# ── 6. COMPETENCIAS ──────────────────────────────────────────────────────────
story.append(Spacer(1, 0.25*cm))
story.append(section('6', 'Competencias Desarrolladas'))
story.append(Spacer(1, 0.2*cm))

skills = [
    [P('Area', th), P('Competencia especifica', th), P('Herramienta / Tecnologia', th)],
    [P('Virtualizacion', tc_b), P('Instalacion y gestion de hipervisor tipo 1, VMs, snapshots y reset automatizado de laboratorio', tc), P('Proxmox VE 8.x · qm CLI', tc)],
    [P('Redes y segmentacion', tc_b), P('Diseno de VLANs 802.1Q, configuracion de bridges Linux, aislamiento de redes de ataque', tc), P('Proxmox bridges · Switch 802.1Q', tc)],
    [P('SIEM y deteccion', tc_b), P('Despliegue de stack de seguridad, creacion de reglas, correlacion de eventos y dashboards', tc), P('Elasticsearch · Kibana · Fleet Server', tc)],
    [P('EDR y telemetria', tc_b), P('Configuracion de agentes endpoint, analisis de process trees, eventos de archivo y red', tc), P('Elastic Defend · Elastic Agent · Sysmon', tc)],
    [P('Red Team / Emulacion APT', tc_b), P('Ejecucion de planes de emulacion MITRE, operacion de frameworks C2, movimiento lateral', tc), P('CALDERA 5.x · Metasploit · Mimikatz', tc)],
    [P('Threat Intelligence', tc_b), P('Mapeo de TTPs en el framework MITRE ATT&CK, analisis de emulation plans CTID', tc), P('ATT&CK Navigator · CTID Library', tc)],
    [P('Analisis forense', tc_b), P('Interpretacion de Sysmon EventIDs, trazas de red, Windows Event Log y process trees', tc), P('Packetbeat · Sysmon · Kibana Discover', tc)],
    [P('Documentacion tecnica', tc_b), P('Redaccion de guias de setup, runbooks APT y reportes de deteccion en formato publicable', tc), P('GitHub Pages · Markdown', tc)],
]
t4 = Table(skills, colWidths=[3.8*cm, 8.4*cm, 4.5*cm])
t4.setStyle(TableStyle([
    ('BACKGROUND', (0,0), (-1,0), DARK_BLUE),
    ('ROWBACKGROUNDS', (0,1), (-1,-1), [LIGHT_GRAY, white]),
    ('GRID', (0,0), (-1,-1), 0.4, MID_GRAY),
    ('LEFTPADDING', (0,0), (-1,-1), 5),
    ('RIGHTPADDING', (0,0), (-1,-1), 5),
    ('TOPPADDING', (0,0), (-1,-1), 4),
    ('BOTTOMPADDING', (0,0), (-1,-1), 4),
    ('VALIGN', (0,0), (-1,-1), 'MIDDLE'),
    ('TEXTCOLOR', (0,1), (0,-1), DARK_BLUE),
]))
story.append(t4)

# PAGE BREAK
story.append(PageBreak())

# ── 7. REQUERIMIENTOS ────────────────────────────────────────────────────────
story.append(section('7', 'Requerimientos Operativos'))
story.append(Spacer(1, 0.2*cm))

reqs = [
    [P('Requerimiento', th), P('Detalle', th), P('Prioridad', th)],
    [P('Reserva exclusiva\nLaboratorio #2', tc_b),
     P('Reserva <b>exclusiva y permanente</b> del Laboratorio #2 durante el periodo del '
       'proyecto (junio – julio 2026). Los servidores Proxmox deben permanecer encendidos '
       'y accesibles sin interrupcion entre sesiones.', tc),
     P('CRITICO', crit)],
    [P('Acceso extendido', tc_b),
     P('Acceso al Laboratorio #2 de <b>lunes a sabado hasta las 22:00 h</b>. Las sesiones '
       'de emulacion de ataques requieren bloques continuos de 3–4 horas.', tc),
     P('CRITICO', crit)],
    [P('Conectividad LAN\n(gestion)', tc_b),
     P('Acceso a la red LAN de la facultad unicamente para descarga inicial de ISOs y '
       'actualizaciones. Las redes de ataque TARGET son <b>completamente aisladas</b> '
       'y no tienen salida a internet.', tc),
     P('Alto', high)],
    [P('Permisos de\nadministrador', tc_b),
     P('Acceso root en las 24 maquinas fisicas para la instalacion de Proxmox VE '
       'y configuracion de red.', tc),
     P('Alto', high)],
    [P('Nota de seguridad', tc_b),
     P('<i>Todos los ataques se ejecutan dentro de la red aislada del Cyber Range. Ningun '
       'trafico de ataque sale hacia la red de la facultad ni hacia Internet. La arquitectura '
       'garantiza aislamiento total mediante VLANs 802.1Q y bridges virtuales Proxmox '
       'sin uplink fisico en la red TARGET.</i>', note),
     P('Info', S('info2', fontSize=9, textColor=DARK_GRAY, alignment=TA_CENTER))],
]
t5 = Table(reqs, colWidths=[3.8*cm, 11.4*cm, 1.5*cm])
t5.setStyle(tbl_style(t5))
story.append(t5)

# ── 8. ENTREGABLES ───────────────────────────────────────────────────────────
story.append(Spacer(1, 0.25*cm))
story.append(section('8', 'Entregables del Proyecto'))
story.append(Spacer(1, 0.2*cm))
for title, desc in [
    ('Cyber Range funcional', '4 instancias independientes (una por grupo) completamente operativas al cierre del proyecto.'),
    ('Reglas de deteccion', 'Set de reglas personalizadas en Elastic SIEM para los TTPs mas relevantes, '
     'documentadas con la tecnica ATT&CK correspondiente.'),
    ('Informe tecnico por grupo', 'Documento de 10–15 paginas: arquitectura, metodologia, tabla de resultados '
     '(Tecnica ATT&CK | Emulada | Detectada | Metodo de deteccion).'),
    ('GitHub Pages', 'Sitio publico con guia de setup del Cyber Range y runbooks individuales para APT29, OilRig y Wizard Spider.'),
    ('Presentacion final', 'Demo en vivo: ejecucion de un escenario APT y observacion en tiempo real de la telemetria en Kibana.'),
]:
    story.append(P(f'•  <b>{title}:</b> {desc}', bullet))

# ── 9. APROBACION ────────────────────────────────────────────────────────────
story.append(Spacer(1, 0.25*cm))
story.append(section('9', 'Aprobacion del Proyecto'))
story.append(Spacer(1, 0.5*cm))

line = '______________________________'
sig_rows = [
    [P(line, sig_sub), P(line, sig_sub), P(line, sig_sub)],
    [P('Responsable del Proyecto', sig_label), P('Docente Asesor', sig_label), P('Jefe de Laboratorio', sig_label)],
    [P('Codigo UNI: _______________', sig_sub), P('Dpto. de: _________________', sig_sub), P('Laboratorio #2  —  FIEE', sig_sub)],
    [P('Firma  /  Fecha', sig_sub), P('Firma  /  Fecha', sig_sub), P('Firma  /  Fecha', sig_sub)],
]
t6 = Table(sig_rows, colWidths=[COL_W/3]*3)
t6.setStyle(TableStyle([
    ('ALIGN', (0,0), (-1,-1), 'CENTER'),
    ('TOPPADDING', (0,0), (-1,-1), 4),
    ('BOTTOMPADDING', (0,0), (-1,-1), 4),
]))
story.append(t6)

# ── LAST PAGE: REGISTRO DE PARTICIPANTES ────────────────────────────────────
story.append(PageBreak())

story.append(banner('REGISTRO DE PARTICIPANTES  —  PROYECTO CYBER RANGE  ·  FIEE-UNI  ·  2026'))
story.append(Spacer(1, 0.3*cm))
story.append(P('Laboratorio #2  —  FIEE-UNI  |  Periodo: Junio – Julio 2026', meta))
story.append(Spacer(1, 0.35*cm))

N = 24
ph = [P(h, th) for h in ['N°', 'Apellidos y Nombres', 'Codigo UNI', 'Correo institucional', 'Grupo', 'Firma']]
prows = [ph]
for i in range(1, N + 1):
    prows.append([
        P(str(i), tc_c), P('', tc), P('', tc), P('', tc),
        P(str((i - 1) // 6 + 1), tc_c), P('', tc),
    ])

t7 = Table(prows,
           colWidths=[0.9*cm, 6.3*cm, 2.6*cm, 4.7*cm, 1.3*cm, 2.9*cm],
           rowHeights=[0.7*cm] + [0.62*cm] * N)
t7.setStyle(tbl_style(t7))
story.append(t7)
story.append(Spacer(1, 0.3*cm))
story.append(P(
    'Los participantes registrados reconocen su compromiso con el desarrollo del Proyecto Cyber Range, '
    'el cumplimiento del cronograma y el uso responsable y etico de la infraestructura y herramientas '
    'de ciberseguridad del Laboratorio #2 — FIEE-UNI.',
    S('pledge', fontName='Helvetica-Oblique', fontSize=8.5, textColor=DARK_GRAY,
      alignment=TA_JUSTIFY, leading=12)
))

doc.build(story)
print(f'PDF generado en: {output}')
