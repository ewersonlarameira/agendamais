(() => {
  'use strict';

  const db = window.supabaseClient;
  const OPENING_HOUR = 8;
  const CLOSING_HOUR = 18;
  const LUNCH_TIME = '12:00';
  const CLINIC_WHATSAPP = '5524999845210';

  let procedures = [];
  let selectedProcedure = null;
  let selectedDate = '';
  let selectedHour = '';

  const byId = (id) => document.getElementById(id);

  function setMessage(id, message = '', type = '') {
    const element = byId(id);
    element.textContent = message;
    element.classList.remove('error', 'success');
    if (type) element.classList.add(type);
  }

  function setBusy(button, busy, label) {
    if (busy) {
      button.dataset.originalLabel = button.textContent;
      button.textContent = label;
      button.disabled = true;
    } else {
      button.textContent = button.dataset.originalLabel || button.textContent;
      button.disabled = false;
      delete button.dataset.originalLabel;
    }
  }

  function show(element, visible) {
    element.classList.toggle('hidden', !visible);
  }

  function localIsoDate(date) {
    const offset = date.getTimezoneOffset() * 60000;
    return new Date(date.getTime() - offset).toISOString().slice(0, 10);
  }

  function formatDate(value) {
    const [year, month, day] = value.split('-');
    return `${day}/${month}/${year}`;
  }

  function normalizePhone(value) {
    return String(value || '').replace(/\D/g, '');
  }

  function friendlyError(error, fallback) {
    if (/rate limit/i.test(error?.message || '')) return 'Muitas tentativas. Aguarde um pouco e tente novamente.';
    return fallback;
  }

  function bindEvents() {
    byId('go-step-2').addEventListener('click', goToSchedule);
    byId('go-step-3').addEventListener('click', () => changeStep('step-3'));
    byId('input-data').addEventListener('change', loadAvailableHours);
    byId('public-booking-form').addEventListener('submit', finishBooking);
    byId('send-whatsapp').addEventListener('click', sendWhatsApp);
    byId('add-google-calendar').addEventListener('click', addGoogleCalendar);
    document.querySelectorAll('[data-back]').forEach((button) => {
      button.addEventListener('click', () => changeStep(button.dataset.back));
    });
  }

  async function initialize() {
    bindEvents();
    const today = new Date();
    const maximum = new Date();
    maximum.setDate(maximum.getDate() + 180);
    byId('input-data').min = localIsoDate(today);
    byId('input-data').max = localIsoDate(maximum);
    await loadProcedures();
  }

  async function loadProcedures() {
    const select = byId('select-procedimento');
    const { data, error } = await db
      .from('procedimentos')
      .select('id,nome,duracao')
      .eq('status', 'Ativo')
      .order('nome');

    select.replaceChildren();
    if (error) {
      select.append(new Option('Serviços indisponíveis', ''));
      setMessage('procedure-public-message', friendlyError(error, 'Não foi possível carregar os serviços.'), 'error');
      return;
    }

    procedures = data || [];
    select.append(new Option('Escolha um procedimento...', ''));
    procedures.forEach((procedure) => {
      select.append(new Option(`${procedure.nome} (${procedure.duracao} min)`, procedure.id));
    });
    if (procedures.length === 0) {
      setMessage('procedure-public-message', 'Nenhum procedimento está disponível no momento.', 'error');
    }
  }

  function changeStep(id) {
    document.querySelectorAll('.step-card').forEach((card) => card.classList.remove('active'));
    byId(id).classList.add('active');
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  function goToSchedule() {
    const procedureId = byId('select-procedimento').value;
    selectedProcedure = procedures.find((procedure) => procedure.id === procedureId) || null;
    if (!selectedProcedure) {
      return setMessage('procedure-public-message', 'Selecione um procedimento para continuar.', 'error');
    }
    setMessage('procedure-public-message');
    selectedHour = '';
    byId('input-data').value = '';
    byId('grid-horarios').replaceChildren();
    show(byId('container-horarios'), false);
    show(byId('go-step-3'), false);
    changeStep('step-2');
  }

  async function loadAvailableHours() {
    selectedDate = byId('input-data').value;
    selectedHour = '';
    show(byId('go-step-3'), false);
    byId('grid-horarios').replaceChildren();
    if (!selectedDate || !selectedProcedure) return;

    show(byId('container-horarios'), true);
    show(byId('loader-horarios'), true);
    setMessage('schedule-public-message');

    const { data, error } = await db.rpc('get_horarios_ocupados', { p_data: selectedDate });
    show(byId('loader-horarios'), false);
    if (error) {
      return setMessage('schedule-public-message', friendlyError(error, 'Não foi possível consultar os horários.'), 'error');
    }

    const occupied = new Set((data || []).map((item) => item.hora));
    renderHours(occupied);
  }

  function renderHours(occupied) {
    const grid = byId('grid-horarios');
    grid.replaceChildren();
    const hours = [];
    for (let hour = OPENING_HOUR; hour < CLOSING_HOUR; hour += 1) {
      hours.push(`${String(hour).padStart(2, '0')}:00`);
    }
    const blocks = Math.max(1, Math.ceil(Number(selectedProcedure.duracao || 60) / 60));
    const today = localIsoDate(new Date());
    const currentHour = new Date().getHours();
    let availableCount = 0;

    hours.forEach((hour, index) => {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'time-slot';
      button.textContent = hour;
      let blocked = hour === LUNCH_TIME || occupied.has(hour);

      if (selectedDate === today && Number.parseInt(hour, 10) <= currentHour) blocked = true;
      for (let offset = 1; !blocked && offset < blocks; offset += 1) {
        const nextHour = hours[index + offset];
        if (!nextHour || nextHour === LUNCH_TIME || occupied.has(nextHour)) blocked = true;
      }

      button.disabled = blocked;
      if (!blocked) {
        availableCount += 1;
        button.addEventListener('click', () => selectHour(hour, button));
      }
      grid.append(button);
    });

    if (availableCount === 0) {
      setMessage('schedule-public-message', 'Não há horários disponíveis nesta data.', 'error');
    }
  }

  function selectHour(hour, button) {
    document.querySelectorAll('.time-slot').forEach((item) => item.classList.remove('selected'));
    button.classList.add('selected');
    selectedHour = hour;
    show(byId('go-step-3'), true);
    setMessage('schedule-public-message');
  }

  async function finishBooking(event) {
    event.preventDefault();
    const name = byId('input-nome').value.trim();
    const whatsapp = byId('input-whatsapp').value.trim();
    const normalizedPhone = normalizePhone(whatsapp);
    if (!selectedProcedure || !selectedDate || !selectedHour) {
      return setMessage('booking-public-message', 'Selecione procedimento, data e horário novamente.', 'error');
    }
    if (name.length < 3 || name.length > 120 || /[<>]/.test(name)) {
      return setMessage('booking-public-message', 'Informe seu nome completo.', 'error');
    }
    if (!/^\d{10,13}$/.test(normalizedPhone)) {
      return setMessage('booking-public-message', 'Informe um WhatsApp válido com DDD.', 'error');
    }

    const button = byId('btn-finalizar');
    setMessage('booking-public-message');
    setBusy(button, true, 'Processando...');
    const { data, error } = await db.rpc('criar_agendamento_publico', {
      p_procedimento_id: selectedProcedure.id,
      p_data: selectedDate,
      p_hora: selectedHour,
      p_nome: name,
      p_whatsapp: normalizedPhone
    });
    setBusy(button, false);

    if (error) {
      return setMessage('booking-public-message', friendlyError(error, 'Não foi possível concluir o agendamento.'), 'error');
    }
    if (!data?.ok) {
      setMessage('booking-public-message', data?.message || 'O horário não está mais disponível.', 'error');
      if (/horário|Horario/.test(data?.message || '')) await loadAvailableHours();
      return;
    }

    fillSummary();
    changeStep('step-4');
  }

  function fillSummary() {
    byId('resumo-proc').textContent = selectedProcedure.nome;
    byId('resumo-data').textContent = formatDate(selectedDate);
    byId('resumo-hora').textContent = selectedHour;
  }

  function sendWhatsApp() {
    const name = byId('input-nome').value.trim();
    const phone = byId('input-whatsapp').value.trim();
    const message = [
      "Olá, clínica Lumina's! Realizei um agendamento pelo aplicativo.",
      '',
      '*Meus dados:*',
      `👤 Nome: ${name}`,
      `📱 Contato: ${phone}`,
      '',
      '*Detalhes do agendamento:*',
      `✨ Procedimento: ${selectedProcedure.nome}`,
      `📅 Data: ${formatDate(selectedDate)}`,
      `⏰ Horário: ${selectedHour}`
    ].join('\n');
    window.open(`https://wa.me/${CLINIC_WHATSAPP}?text=${encodeURIComponent(message)}`, '_blank', 'noopener,noreferrer');
  }

  function addGoogleCalendar() {
    const compactDate = selectedDate.replaceAll('-', '');
    const startHour = Number.parseInt(selectedHour, 10);
    const endHour = startHour + Math.ceil(Number(selectedProcedure.duracao || 60) / 60);
    const start = `${compactDate}T${String(startHour).padStart(2, '0')}0000`;
    const end = `${compactDate}T${String(endHour).padStart(2, '0')}0000`;
    const parameters = new URLSearchParams({
      action: 'TEMPLATE',
      text: `Lumina's Clínica: ${selectedProcedure.nome}`,
      dates: `${start}/${end}`,
      details: "Agendamento na Lumina's Clínica Estética.",
      ctz: 'America/Sao_Paulo'
    });
    window.open(`https://calendar.google.com/calendar/render?${parameters.toString()}`, '_blank', 'noopener,noreferrer');
  }

  initialize();
})();
