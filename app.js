(() => {
  'use strict';

  const db = window.supabaseClient;
  const MENU_IDS = ['agenda', 'pacientes', 'procedimentos', 'documentos', 'profissionais', 'configuracoes'];
  const PROCEDURE_FIELDS = 'id,nome,duracao,valor,categoria,status,especialidade,descricao,beneficios,cuidados_pos,retorno,observacao_preco';
  const PROFILE_FIELDS = 'id,nome,especialidade,nick,permissoes,auth_user_id,email,ativo,legacy_claimed_at';

  let currentUser = null;
  let currentProfile = null;
  let permissions = new Set();
  let patients = [];
  let procedures = [];
  let professionals = [];
  let appointments = [];
  let anamneses = [];
  let selectedBookingHour = '';
  let handledUserId = null;

  let openingTime = localStorage.getItem('lumina_abertura') || '08:00';
  let closingTime = localStorage.getItem('lumina_fechamento') || '18:00';
  let lunchTime = localStorage.getItem('lumina_almoco') || '12:00';
  let scheduleHours = [];
  let selectedDateObject = new Date();
  let selectedDate = toLocalIsoDate(selectedDateObject);

  const QUESTIONS = {
    injetaveis: [
      'Possui alergia a anestésicos, medicamentos ou substâncias sintéticas?',
      'Tem alguma doença autoimune (ex.: lúpus ou vitiligo)?',
      'Está usando antibióticos, anti-inflamatórios ou anticoagulantes?',
      'Tem histórico de herpes labial ou facial?',
      'Está gestante ou amamentando?'
    ],
    facial: [
      'Faz uso de ácidos ou produtos clareadores em casa?',
      'Fez uso de Roacutan nos últimos seis meses?',
      'Tem histórico de alergia a cosméticos?',
      'Costuma ter muita exposição ao sol sem proteção?',
      'Possui histórico pessoal ou familiar de câncer de pele?'
    ],
    corporal: [
      'Possui prótese metálica, DIU de cobre ou marca-passo?',
      'Tem histórico de trombose ou problemas circulatórios?',
      'Possui pressão alta ou diabetes descompensada?',
      'Pratica atividade física regularmente?'
    ],
    endolaser: [
      'Possui problemas de cicatrização, queloides ou cicatriz hipertrófica?',
      'Fez alguma cirurgia recente na região a ser tratada?',
      'Tem diabetes ou hipertensão descompensada?',
      'Está utilizando medicamento de uso contínuo?'
    ],
    massagem: [
      'Possui fraturas recentes, osteoporose ou problemas na coluna?',
      'Tem histórico de trombose venosa profunda?',
      'Possui processo inflamatório ou infeccioso agudo?',
      'Está gestante? Se sim, informe as semanas.'
    ],
    laser: [
      'Tomou sol na região nos últimos 15 dias?',
      'Faz uso de ácidos na região que será depilada?',
      'Possui tatuagem no local da aplicação?',
      'Tem histórico de foliculite severa?'
    ],
    nutricao: [
      'Possui alergia ou intolerância alimentar diagnosticada?',
      'Tem problemas intestinais, como constipação, diarreia ou dores?',
      'Possui diagnóstico de diabetes, colesterol alto ou hipertensão?',
      'Faz uso de suplementação ou vitaminas?'
    ],
    geral: [
      'Possui alguma alergia diagnosticada?',
      'Está gestante ou amamentando?',
      'Faz uso contínuo de algum medicamento?',
      'Já teve complicações em procedimentos estéticos anteriores?'
    ]
  };

  const byId = (id) => document.getElementById(id);

  function setMessage(id, message = '', type = '') {
    const element = byId(id);
    if (!element) return;
    element.textContent = message;
    element.classList.remove('error', 'success');
    if (type) element.classList.add(type);
  }

  function setBusy(button, busy, busyLabel) {
    if (!button) return;
    if (busy) {
      button.dataset.originalLabel = button.textContent;
      button.textContent = busyLabel;
      button.disabled = true;
    } else {
      button.textContent = button.dataset.originalLabel || button.textContent;
      button.disabled = false;
      delete button.dataset.originalLabel;
    }
  }

  function showElement(element, show) {
    element?.classList.toggle('hidden', !show);
  }

  function parsePermissions(value) {
    if (Array.isArray(value)) return value.filter((item) => typeof item === 'string');
    if (typeof value === 'string') {
      try {
        const parsed = JSON.parse(value);
        return Array.isArray(parsed) ? parsed.filter((item) => typeof item === 'string') : [];
      } catch {
        return [];
      }
    }
    return [];
  }

  function hasPermission(permission) {
    return permissions.has(permission);
  }

  function toLocalIsoDate(date) {
    const offset = date.getTimezoneOffset() * 60000;
    return new Date(date.getTime() - offset).toISOString().slice(0, 10);
  }

  function formatDate(dateString) {
    const [year, month, day] = dateString.split('-');
    return `${day}/${month}/${year}`;
  }

  function formatDateTime(isoString) {
    const date = new Date(isoString);
    return `${date.toLocaleDateString('pt-BR')} às ${date.toLocaleTimeString('pt-BR', {
      hour: '2-digit',
      minute: '2-digit'
    })}`;
  }

  function normalizePhone(value) {
    return String(value || '').replace(/\D/g, '');
  }

  function friendlyError(error, fallback = 'Não foi possível concluir a operação.') {
    if (!error) return fallback;
    if (error.code === '23505') return 'Já existe um registro com esses dados.';
    if (error.code === '42501' || /row-level security|permission denied/i.test(error.message || '')) {
      return 'Seu perfil não tem permissão para esta operação.';
    }
    if (/invalid login credentials/i.test(error.message || '')) return 'E-mail ou senha inválidos.';
    if (/email not confirmed/i.test(error.message || '')) return 'Confirme o e-mail antes de entrar.';
    if (/user already registered/i.test(error.message || '')) return 'Este e-mail já possui acesso.';
    return fallback;
  }

  function reportError(error, messageId, fallback) {
    console.error(error?.code || 'app_error', error?.message || error);
    setMessage(messageId, friendlyError(error, fallback), 'error');
  }

  function emptyRow(columnCount, label) {
    const row = document.createElement('tr');
    const cell = document.createElement('td');
    cell.colSpan = columnCount;
    cell.className = 'empty-row';
    cell.textContent = label;
    row.append(cell);
    return row;
  }

  function makeButton(label, onClick, danger = false) {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = `btn-action${danger ? ' danger' : ''}`;
    button.textContent = label;
    button.addEventListener('click', onClick);
    return button;
  }

  function createCell(text = '') {
    const cell = document.createElement('td');
    cell.textContent = text == null || text === '' ? '-' : String(text);
    return cell;
  }

  function buildScheduleHours() {
    const start = Number.parseInt(openingTime.split(':')[0], 10);
    const end = Number.parseInt(closingTime.split(':')[0], 10);
    scheduleHours = [];
    for (let hour = start; hour < end; hour += 1) {
      scheduleHours.push(`${String(hour).padStart(2, '0')}:00`);
    }
  }

  function bindEvents() {
    byId('login-form').addEventListener('submit', signIn);
    byId('signup-form').addEventListener('submit', signUp);
    byId('show-signup').addEventListener('click', () => {
      showElement(byId('signup-panel'), byId('signup-panel').classList.contains('hidden'));
    });
    byId('forgot-password').addEventListener('click', requestPasswordReset);
    byId('recovery-form').addEventListener('submit', updateRecoveredPassword);
    byId('invite-claim-form').addEventListener('submit', claimInvite);
    byId('legacy-claim-form').addEventListener('submit', claimLegacyProfile);
    byId('claim-logout').addEventListener('click', signOut);
    byId('btn-logout').addEventListener('click', signOut);

    document.querySelectorAll('[data-view]').forEach((button) => {
      button.addEventListener('click', () => changeView(button.dataset.view));
    });
    document.querySelectorAll('[data-document-tab]').forEach((button) => {
      button.addEventListener('click', () => changeDocumentTab(button.dataset.documentTab, button));
    });

    byId('date-prev').addEventListener('click', () => changeDate(-1));
    byId('date-next').addEventListener('click', () => changeDate(1));
    byId('data-agenda').addEventListener('change', selectDateFromInput);
    byId('patient-form').addEventListener('submit', savePatient);
    byId('procedure-form').addEventListener('submit', saveProcedure);
    byId('btn-cancelar-edit-proc').addEventListener('click', cancelProcedureEdit);
    byId('professional-form').addEventListener('submit', saveProfessional);
    byId('btn-cancelar-edit').addEventListener('click', cancelProfessionalEdit);
    byId('copy-activation-code').addEventListener('click', copyActivationCode);
    byId('schedule-form').addEventListener('submit', saveScheduleSettings);
    byId('anamnese-procedimento').addEventListener('change', buildAnamneseForm);
    byId('btn-salvar-anamnese').addEventListener('click', saveAnamnese);
    byId('booking-form').addEventListener('submit', createInternalBooking);
    byId('close-booking-modal').addEventListener('click', closeBookingModal);
    byId('close-anamnese-modal').addEventListener('click', () => closeModal('modal-view-anamnese'));

    document.querySelectorAll('.modal-overlay').forEach((modal) => {
      modal.addEventListener('click', (event) => {
        if (event.target === modal) closeModal(modal.id);
      });
    });
    document.addEventListener('keydown', (event) => {
      if (event.key === 'Escape') {
        closeModal('modal-agendamento');
        closeModal('modal-view-anamnese');
      }
    });
  }

  async function initialize() {
    bindEvents();
    buildScheduleHours();
    byId('data-agenda').value = selectedDate;
    byId('conf-abertura').value = openingTime;
    byId('conf-fechamento').value = closingTime;
    byId('conf-almoco').value = lunchTime;

    const { data, error } = await db.auth.getSession();
    if (error) reportError(error, 'login-message', 'Não foi possível verificar a sessão.');
    await applySession(data?.session || null);

    db.auth.onAuthStateChange((authEvent, session) => {
      window.setTimeout(() => {
        if (authEvent === 'PASSWORD_RECOVERY') showRecovery();
        else applySession(session);
      }, 0);
    });
  }

  async function signIn(event) {
    event.preventDefault();
    const button = byId('login-submit');
    const email = byId('login-email').value.trim();
    const password = byId('login-password').value;
    setMessage('login-message');
    setBusy(button, true, 'Entrando...');

    const { data, error } = await db.auth.signInWithPassword({ email, password });
    setBusy(button, false);
    if (error) return reportError(error, 'login-message', 'Não foi possível entrar.');
    await applySession(data.session, true);
  }

  async function signUp(event) {
    event.preventDefault();
    const button = byId('signup-submit');
    const email = byId('signup-email').value.trim();
    const password = byId('signup-password').value;
    if (password.length < 8) {
      return setMessage('signup-message', 'A senha deve ter pelo menos 8 caracteres.', 'error');
    }

    setMessage('signup-message');
    setBusy(button, true, 'Criando...');
    const redirectUrl = window.location.href.split(/[?#]/)[0];
    const { data, error } = await db.auth.signUp({
      email,
      password,
      options: { emailRedirectTo: redirectUrl }
    });
    setBusy(button, false);

    if (error) return reportError(error, 'signup-message', 'Não foi possível criar o acesso.');
    if (data.session) {
      setMessage('signup-message', 'Acesso criado. Agora vincule seu perfil.', 'success');
      await applySession(data.session, true);
    } else {
      setMessage('signup-message', 'Verifique seu e-mail, confirme o cadastro e depois entre.', 'success');
    }
  }

  async function signOut() {
    await db.auth.signOut();
    handledUserId = null;
    showLogin();
  }

  async function requestPasswordReset() {
    const email = byId('login-email').value.trim();
    if (!email) return setMessage('login-message', 'Informe seu e-mail para recuperar a senha.', 'error');
    const redirectTo = window.location.href.split(/[?#]/)[0];
    const { error } = await db.auth.resetPasswordForEmail(email, { redirectTo });
    if (error) return reportError(error, 'login-message', 'Não foi possível solicitar a recuperação.');
    setMessage('login-message', 'Se o e-mail estiver cadastrado, enviaremos um link de recuperação.', 'success');
  }

  function showRecovery() {
    document.body.className = 'auth-page';
    showElement(byId('login-screen'), true);
    showElement(byId('login-form'), false);
    showElement(byId('show-signup'), false);
    showElement(byId('forgot-password'), false);
    showElement(byId('signup-panel'), false);
    showElement(byId('claim-panel'), false);
    showElement(byId('recovery-panel'), true);
    byId('app-screen').classList.remove('active');
    setMessage('recovery-message', 'Crie uma senha com pelo menos 8 caracteres.');
  }

  async function updateRecoveredPassword(event) {
    event.preventDefault();
    const password = byId('recovery-password').value;
    const button = byId('recovery-submit');
    if (password.length < 8) {
      return setMessage('recovery-message', 'A senha deve ter pelo menos 8 caracteres.', 'error');
    }
    setBusy(button, true, 'Salvando...');
    const { error } = await db.auth.updateUser({ password });
    setBusy(button, false);
    if (error) return reportError(error, 'recovery-message', 'Não foi possível atualizar a senha.');
    byId('recovery-form').reset();
    setMessage('recovery-message', 'Senha atualizada.', 'success');
    const session = (await db.auth.getSession()).data.session;
    await applySession(session, true);
  }

  async function applySession(session, force = false) {
    const user = session?.user || null;
    if (!user) {
      handledUserId = null;
      showLogin();
      return;
    }
    if (!force && handledUserId === user.id && currentProfile) return;

    currentUser = user;
    const { data: profile, error } = await db
      .from('usuarios')
      .select(PROFILE_FIELDS)
      .eq('auth_user_id', user.id)
      .maybeSingle();

    if (error) {
      showLogin();
      return reportError(error, 'login-message', 'O perfil não pôde ser carregado.');
    }

    handledUserId = user.id;
    if (!profile) {
      currentProfile = null;
      showClaim(user);
      return;
    }

    if (!profile.ativo) {
      await db.auth.signOut();
      showLogin('Este perfil está inativo. Fale com a administradora.');
      return;
    }

    currentProfile = profile;
    permissions = new Set(parsePermissions(profile.permissoes).filter((item) => MENU_IDS.includes(item)));
    if (permissions.size === 0) {
      await db.auth.signOut();
      showLogin('Este perfil não possui permissões ativas.');
      return;
    }

    showApp();
    await loadAuthorizedData();
  }

  function showLogin(message = '') {
    currentUser = null;
    currentProfile = null;
    permissions = new Set();
    document.body.className = 'auth-page';
    showElement(byId('login-screen'), true);
    showElement(byId('login-form'), true);
    showElement(byId('show-signup'), true);
    showElement(byId('forgot-password'), true);
    showElement(byId('claim-panel'), false);
    showElement(byId('recovery-panel'), false);
    byId('app-screen').classList.remove('active');
    if (message) setMessage('login-message', message, 'error');
  }

  function showClaim(user) {
    document.body.className = 'auth-page';
    showElement(byId('login-screen'), true);
    showElement(byId('login-form'), false);
    showElement(byId('show-signup'), false);
    showElement(byId('forgot-password'), false);
    showElement(byId('signup-panel'), false);
    showElement(byId('claim-panel'), true);
    showElement(byId('recovery-panel'), false);
    byId('claim-user').textContent = `Conta autenticada: ${user.email || 'e-mail confirmado'}`;
    byId('app-screen').classList.remove('active');
    setMessage('claim-message', 'Informe o código de ativação ou use o nickname e a senha antigos.');
  }

  function showApp() {
    document.body.className = '';
    showElement(byId('login-screen'), false);
    showElement(byId('recovery-panel'), false);
    byId('app-screen').classList.add('active');
    byId('user-summary').textContent = `${currentProfile.nome} · ${currentProfile.email || currentUser.email || ''}`;
    MENU_IDS.forEach((menu) => showElement(byId(`menu-${menu}`), hasPermission(menu)));
    changeView([...permissions][0]);
  }

  async function claimInvite(event) {
    event.preventDefault();
    const code = byId('claim-code').value.trim();
    if (!code) return setMessage('claim-message', 'Informe o código de ativação.', 'error');
    setMessage('claim-message', 'Validando código...');
    const { data, error } = await db.rpc('claim_access_invite', { p_code: code });
    if (error) return reportError(error, 'claim-message', 'Não foi possível validar o código.');
    if (!data?.ok) return setMessage('claim-message', data?.message || 'Código inválido.', 'error');
    setMessage('claim-message', data.message, 'success');
    const session = (await db.auth.getSession()).data.session;
    await applySession(session, true);
  }

  async function claimLegacyProfile(event) {
    event.preventDefault();
    const nick = byId('claim-nick').value.trim();
    const password = byId('claim-password').value;
    if (!nick || !password) return setMessage('claim-message', 'Informe nickname e senha antigos.', 'error');
    setMessage('claim-message', 'Vinculando perfil...');
    const { data, error } = await db.rpc('claim_legacy_profile', {
      p_nick: nick,
      p_legacy_password: password
    });
    byId('claim-password').value = '';
    if (error) return reportError(error, 'claim-message', 'Não foi possível vincular o perfil.');
    if (!data?.ok) return setMessage('claim-message', data?.message || 'Dados inválidos.', 'error');
    setMessage('claim-message', data.message, 'success');
    const session = (await db.auth.getSession()).data.session;
    await applySession(session, true);
  }

  function changeView(viewId) {
    if (!viewId || !hasPermission(viewId)) return;
    document.querySelectorAll('.view').forEach((view) => view.classList.remove('active'));
    document.querySelectorAll('[data-view]').forEach((button) => button.classList.remove('active'));
    byId(viewId)?.classList.add('active');
    byId(`menu-${viewId}`)?.classList.add('active');
    if (viewId === 'configuracoes') updateDashboard();
  }

  function changeDocumentTab(tabId, button) {
    document.querySelectorAll('.sub-tab-content').forEach((tab) => tab.classList.remove('active'));
    document.querySelectorAll('.sub-tab-btn').forEach((tabButton) => tabButton.classList.remove('active'));
    byId(tabId)?.classList.add('active');
    button.classList.add('active');
  }

  async function loadAuthorizedData() {
    const jobs = [];
    const needsPatients = ['agenda', 'pacientes', 'documentos'].some(hasPermission);
    const needsProcedures = ['agenda', 'procedimentos', 'documentos', 'configuracoes'].some(hasPermission);

    if (needsPatients) jobs.push(loadPatients());
    if (needsProcedures) jobs.push(loadProcedures());
    if (hasPermission('profissionais')) jobs.push(loadProfessionals());
    if (hasPermission('documentos')) jobs.push(loadAnamneses());
    await Promise.all(jobs);

    if (hasPermission('agenda') || hasPermission('configuracoes')) await loadAgenda();
  }

  function changeDate(days) {
    selectedDateObject.setDate(selectedDateObject.getDate() + days);
    selectedDate = toLocalIsoDate(selectedDateObject);
    byId('data-agenda').value = selectedDate;
    loadAgenda();
  }

  function selectDateFromInput() {
    const value = byId('data-agenda').value;
    if (!value) return;
    selectedDate = value;
    selectedDateObject = new Date(`${value}T12:00:00`);
    loadAgenda();
  }

  async function loadAgenda() {
    setMessage('agenda-message', 'Carregando agenda...');
    const { data, error } = await db
      .from('agendamentos')
      .select('id,id_agrupador,data_agendamento,hora,paciente_id,procedimento_id,paciente_nome,procedimento_nome,is_continuacao')
      .eq('data_agendamento', selectedDate)
      .order('hora');
    if (error) return reportError(error, 'agenda-message', 'Não foi possível carregar a agenda.');
    appointments = data || [];
    renderAgenda();
    setMessage('agenda-message');
    updateDashboard();
  }

  function renderAgenda() {
    const container = byId('grade-agenda');
    container.replaceChildren();
    const allHours = [...new Set([...scheduleHours, ...appointments.map((item) => item.hora)])].sort();

    allHours.forEach((hour) => {
      const row = document.createElement('div');
      row.className = 'agenda-row';
      const time = document.createElement('div');
      time.className = 'agenda-time';
      time.textContent = hour;
      const appointment = appointments.find((item) => item.hora === hour);
      let slot;

      if (appointment) {
        slot = document.createElement('div');
        slot.className = `agenda-slot ${appointment.is_continuacao ? 'slot-continuation' : 'slot-busy'}`;
        const description = document.createElement('span');
        description.textContent = appointment.is_continuacao
          ? `↳ Continuação: ${appointment.paciente_nome}`
          : `👤 ${appointment.paciente_nome} — ${appointment.procedimento_nome}`;
        slot.append(description);
        if (!appointment.is_continuacao && hasPermission('agenda')) {
          const cancel = document.createElement('button');
          cancel.type = 'button';
          cancel.className = 'btn-cancel';
          cancel.textContent = 'Desmarcar';
          cancel.addEventListener('click', () => cancelBooking(appointment.id_agrupador));
          slot.append(cancel);
        }
      } else if (hour === `${lunchTime.split(':')[0]}:00`) {
        slot = document.createElement('div');
        slot.className = 'agenda-slot slot-lunch';
        slot.textContent = 'Almoço';
      } else {
        slot = document.createElement('button');
        slot.type = 'button';
        slot.className = 'agenda-slot slot-free';
        slot.textContent = hasPermission('agenda') ? 'Livre (agendar)' : 'Livre';
        if (hasPermission('agenda')) slot.addEventListener('click', () => openBookingModal(hour));
        else slot.disabled = true;
      }

      row.append(time, slot);
      container.append(row);
    });
  }

  function openBookingModal(hour) {
    selectedBookingHour = hour;
    byId('modal-horario').textContent = `${formatDate(selectedDate)} — ${hour}`;
    setMessage('booking-message');
    byId('modal-agendamento').classList.add('open');
    byId('modal-paciente-nome').focus();
  }

  function closeBookingModal() {
    closeModal('modal-agendamento');
    byId('booking-form').reset();
    setMessage('booking-message');
  }

  function closeModal(id) {
    byId(id)?.classList.remove('open');
  }

  async function createInternalBooking(event) {
    event.preventDefault();
    const button = byId('booking-submit');
    const name = byId('modal-paciente-nome').value.trim();
    const phone = byId('modal-paciente-whatsapp').value.trim();
    const procedureId = byId('modal-procedimento').value;
    const existingPatient = patients.find((item) => item.nome.localeCompare(name, 'pt-BR', { sensitivity: 'accent' }) === 0);

    if (!name || !procedureId) return setMessage('booking-message', 'Informe paciente e procedimento.', 'error');
    if (!existingPatient && phone && !/^\d{10,13}$/.test(normalizePhone(phone))) {
      return setMessage('booking-message', 'Informe um WhatsApp válido ou deixe o campo vazio.', 'error');
    }

    setBusy(button, true, 'Agendando...');
    const { data, error } = await db.rpc('criar_agendamento_interno', {
      p_procedimento_id: procedureId,
      p_data: selectedDate,
      p_hora: selectedBookingHour,
      p_paciente_id: existingPatient?.id || null,
      p_nome: name,
      p_whatsapp: phone || null
    });
    setBusy(button, false);
    if (error) return reportError(error, 'booking-message', 'Não foi possível criar o agendamento.');
    if (!data?.ok) return setMessage('booking-message', data?.message || 'Horário indisponível.', 'error');

    closeBookingModal();
    await Promise.all([loadAgenda(), loadPatients()]);
  }

  async function cancelBooking(groupId) {
    if (!window.confirm('Tem certeza que deseja desmarcar este atendimento?')) return;
    const { error } = await db.from('agendamentos').delete().eq('id_agrupador', groupId);
    if (error) return reportError(error, 'agenda-message', 'Não foi possível desmarcar o atendimento.');
    await loadAgenda();
  }

  async function savePatient(event) {
    event.preventDefault();
    const name = byId('pac-nome').value.trim();
    const phone = byId('pac-whatsapp').value.trim();
    if (name.length < 3) return setMessage('patient-message', 'Informe o nome completo.', 'error');
    if (phone && !/^\d{10,13}$/.test(normalizePhone(phone))) {
      return setMessage('patient-message', 'Informe um WhatsApp válido.', 'error');
    }

    const { error } = await db.from('pacientes').insert({
      nome: name,
      whatsapp: phone || null,
      whatsapp_normalizado: normalizePhone(phone) || null
    });
    if (error) return reportError(error, 'patient-message', 'Não foi possível cadastrar o paciente.');
    byId('patient-form').reset();
    setMessage('patient-message', 'Paciente cadastrado.', 'success');
    await loadPatients();
  }

  async function loadPatients() {
    const { data, error } = await db.from('pacientes').select('id,nome,whatsapp').order('nome');
    if (error) return reportError(error, 'patient-message', 'Não foi possível carregar os pacientes.');
    patients = data || [];
    renderPatients();
  }

  function renderPatients() {
    const tbody = byId('tabela-pacientes');
    const datalist = byId('lista-pacientes');
    const anamneseSelect = byId('anamnese-paciente');
    tbody.replaceChildren();
    datalist.replaceChildren();
    anamneseSelect.replaceChildren(new Option('Selecione...', ''));

    if (patients.length === 0) tbody.append(emptyRow(2, 'Nenhum paciente cadastrado.'));
    patients.forEach((patient) => {
      const row = document.createElement('tr');
      row.append(createCell(patient.nome), createCell(patient.whatsapp));
      tbody.append(row);
      const option = document.createElement('option');
      option.value = patient.nome;
      datalist.append(option);
      anamneseSelect.append(new Option(patient.nome, patient.nome));
    });
  }

  async function saveProcedure(event) {
    event.preventDefault();
    const id = byId('proc-id-edit').value;
    const payload = {
      nome: byId('proc-nome').value.trim(),
      categoria: byId('proc-categoria').value,
      status: byId('proc-status').value,
      duracao: Number.parseInt(byId('proc-duracao').value, 10),
      valor: Number.parseFloat(byId('proc-valor').value) || 0,
      especialidade: byId('proc-especialidade').value.trim() || null,
      descricao: byId('proc-descricao').value.trim() || null,
      beneficios: byId('proc-beneficios').value.trim() || null,
      cuidados_pos: byId('proc-cuidados').value.trim() || null,
      retorno: byId('proc-retorno').value.trim() || null,
      observacao_preco: byId('proc-obs-preco').value.trim() || null
    };
    if (payload.nome.length < 2) return setMessage('procedure-message', 'Informe o nome do procedimento.', 'error');

    const query = id
      ? db.from('procedimentos').update(payload).eq('id', id)
      : db.from('procedimentos').insert(payload);
    const { error } = await query;
    if (error) return reportError(error, 'procedure-message', 'Não foi possível salvar o procedimento.');
    cancelProcedureEdit();
    setMessage('procedure-message', id ? 'Procedimento atualizado.' : 'Procedimento cadastrado.', 'success');
    await loadProcedures();
  }

  function editProcedure(id) {
    const procedure = procedures.find((item) => item.id === id);
    if (!procedure) return;
    byId('proc-id-edit').value = procedure.id;
    byId('proc-nome').value = procedure.nome;
    byId('proc-categoria').value = procedure.categoria || 'Outros';
    byId('proc-status').value = procedure.status || 'Ativo';
    byId('proc-duracao').value = procedure.duracao || 60;
    byId('proc-valor').value = procedure.valor || 0;
    byId('proc-especialidade').value = procedure.especialidade || '';
    byId('proc-descricao').value = procedure.descricao || '';
    byId('proc-beneficios').value = procedure.beneficios || '';
    byId('proc-cuidados').value = procedure.cuidados_pos || '';
    byId('proc-retorno').value = procedure.retorno || '';
    byId('proc-obs-preco').value = procedure.observacao_preco || '';
    byId('btn-salvar-proc').textContent = 'Atualizar procedimento';
    showElement(byId('btn-cancelar-edit-proc'), true);
    byId('main-content').scrollTo({ top: 0, behavior: 'smooth' });
  }

  function cancelProcedureEdit() {
    byId('procedure-form').reset();
    byId('proc-id-edit').value = '';
    byId('proc-duracao').value = '60';
    byId('btn-salvar-proc').textContent = 'Salvar procedimento';
    showElement(byId('btn-cancelar-edit-proc'), false);
  }

  async function setProcedureStatus(id, active) {
    if (!active && !window.confirm('Mover este procedimento para a lixeira?')) return;
    const { error } = await db.from('procedimentos').update({ status: active ? 'Ativo' : 'Inativo' }).eq('id', id);
    if (error) return reportError(error, 'procedure-message', 'Não foi possível alterar o status.');
    await loadProcedures();
  }

  async function loadProcedures() {
    const { data, error } = await db.from('procedimentos').select(PROCEDURE_FIELDS).order('categoria').order('nome');
    if (error) return reportError(error, 'procedure-message', 'Não foi possível carregar os procedimentos.');
    procedures = data || [];
    renderProcedures();
  }

  function renderProcedures() {
    const activeBody = byId('tabela-procedimentos-ativos');
    const inactiveBody = byId('tabela-procedimentos-inativos');
    const bookingSelect = byId('modal-procedimento');
    const anamneseSelect = byId('anamnese-procedimento');
    activeBody.replaceChildren();
    inactiveBody.replaceChildren();
    bookingSelect.replaceChildren(new Option('Selecione...', ''));
    anamneseSelect.replaceChildren(new Option('Selecione...', ''));

    const activeProcedures = procedures.filter((item) => item.status !== 'Inativo');
    const inactiveProcedures = procedures.filter((item) => item.status === 'Inativo');
    if (activeProcedures.length === 0) activeBody.append(emptyRow(5, 'Nenhum procedimento ativo.'));
    if (inactiveProcedures.length === 0) inactiveBody.append(emptyRow(5, 'Nenhum procedimento inativo.'));

    procedures.forEach((procedure) => {
      const row = document.createElement('tr');
      const value = Number(procedure.valor || 0).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
      row.append(
        createCell(procedure.categoria),
        createCell(procedure.nome),
        createCell(`${procedure.duracao} min`),
        createCell(value)
      );
      const actions = document.createElement('td');
      if (procedure.status === 'Inativo') {
        actions.append(makeButton('♻️ Restaurar', () => setProcedureStatus(procedure.id, true)));
        inactiveBody.append(row);
      } else {
        actions.append(
          makeButton('✏️ Editar', () => editProcedure(procedure.id)),
          makeButton('🗑️ Lixeira', () => setProcedureStatus(procedure.id, false), true)
        );
        activeBody.append(row);
        bookingSelect.append(new Option(`${procedure.nome} (${procedure.duracao} min)`, procedure.id));
        anamneseSelect.append(new Option(procedure.nome, procedure.nome));
      }
      row.append(actions);
    });
  }

  async function loadProfessionals() {
    const { data, error } = await db.from('usuarios').select(PROFILE_FIELDS).order('nome');
    if (error) return reportError(error, 'professional-message', 'Não foi possível carregar os profissionais.');
    professionals = data || [];
    renderProfessionals();
  }

  async function saveProfessional(event) {
    event.preventDefault();
    const id = byId('cad-id-edit').value;
    const payload = {
      nome: byId('cad-nome').value.trim(),
      especialidade: byId('cad-especialidade').value.trim() || null,
      nick: byId('cad-nick').value.trim(),
      permissoes: MENU_IDS.filter((permission) => byId(`perm-${permission}`).checked),
      ativo: true
    };
    if (payload.nome.length < 3 || payload.nick.length < 2) {
      return setMessage('professional-message', 'Informe nome e nickname válidos.', 'error');
    }
    if (payload.permissoes.length === 0) {
      return setMessage('professional-message', 'Selecione pelo menos uma permissão.', 'error');
    }

    if (id) {
      const { error } = await db.from('usuarios').update(payload).eq('id', id);
      if (error) return reportError(error, 'professional-message', 'Não foi possível atualizar o profissional.');
      cancelProfessionalEdit();
      setMessage('professional-message', 'Profissional atualizado.', 'success');
      await loadProfessionals();
      return;
    }

    const { data: created, error } = await db.from('usuarios').insert(payload).select('id').single();
    if (error) return reportError(error, 'professional-message', 'Não foi possível cadastrar. O nickname pode já existir.');
    const codeCreated = await generateActivationCode(created.id);
    cancelProfessionalEdit();
    setMessage('professional-message', codeCreated ? 'Profissional cadastrado.' : 'Perfil criado; gere um código na lista.', codeCreated ? 'success' : 'error');
    await loadProfessionals();
  }

  function editProfessional(id) {
    const professional = professionals.find((item) => item.id === id);
    if (!professional) return;
    byId('cad-id-edit').value = professional.id;
    byId('cad-nome').value = professional.nome;
    byId('cad-especialidade').value = professional.especialidade || '';
    byId('cad-nick').value = professional.nick;
    const professionalPermissions = parsePermissions(professional.permissoes);
    MENU_IDS.forEach((permission) => {
      byId(`perm-${permission}`).checked = professionalPermissions.includes(permission);
    });
    byId('btn-salvar-prof').textContent = 'Atualizar profissional';
    showElement(byId('btn-cancelar-edit'), true);
    byId('main-content').scrollTo({ top: 0, behavior: 'smooth' });
  }

  function cancelProfessionalEdit() {
    byId('professional-form').reset();
    byId('cad-id-edit').value = '';
    byId('perm-agenda').checked = true;
    byId('perm-pacientes').checked = true;
    byId('btn-salvar-prof').textContent = 'Salvar profissional';
    showElement(byId('btn-cancelar-edit'), false);
  }

  async function setProfessionalStatus(id, active) {
    if (id === currentProfile.id) {
      return setMessage('professional-message', 'Você não pode inativar o próprio perfil.', 'error');
    }
    if (!active && !window.confirm('Inativar este profissional?')) return;
    const { error } = await db.from('usuarios').update({ ativo: active }).eq('id', id);
    if (error) return reportError(error, 'professional-message', 'Não foi possível alterar o status.');
    await loadProfessionals();
  }

  async function generateActivationCode(profileId) {
    setMessage('professional-message', 'Gerando código de ativação...');
    const { data, error } = await db.rpc('create_access_invite', { p_profile_id: profileId });
    if (error) {
      reportError(error, 'professional-message', 'Não foi possível gerar o código de ativação.');
      return false;
    }
    byId('activation-code').textContent = data;
    showElement(byId('activation-box'), true);
    return true;
  }

  async function copyActivationCode() {
    const code = byId('activation-code').textContent;
    if (!code) return;
    try {
      await navigator.clipboard.writeText(code);
      setMessage('professional-message', 'Código copiado.', 'success');
    } catch {
      setMessage('professional-message', 'Selecione e copie o código manualmente.', 'error');
    }
  }

  function renderProfessionals() {
    const activeBody = byId('tabela-profissionais-ativos');
    const inactiveBody = byId('tabela-profissionais-inativos');
    activeBody.replaceChildren();
    inactiveBody.replaceChildren();
    const active = professionals.filter((item) => item.ativo);
    const inactive = professionals.filter((item) => !item.ativo);
    if (active.length === 0) activeBody.append(emptyRow(5, 'Nenhum profissional ativo.'));
    if (inactive.length === 0) inactiveBody.append(emptyRow(5, 'Nenhum profissional inativo.'));

    professionals.forEach((professional) => {
      const row = document.createElement('tr');
      row.append(
        createCell(professional.nome),
        createCell(professional.especialidade),
        createCell(professional.nick),
        createCell(professional.auth_user_id ? 'Vinculado' : 'Aguardando ativação')
      );
      const actions = document.createElement('td');
      if (professional.ativo) {
        actions.append(makeButton('✏️ Editar', () => editProfessional(professional.id)));
        if (!professional.auth_user_id) {
          actions.append(makeButton('🔑 Gerar código', () => generateActivationCode(professional.id)));
        }
        if (professional.id !== currentProfile.id) {
          actions.append(makeButton('🗑️ Inativar', () => setProfessionalStatus(professional.id, false), true));
        }
        activeBody.append(row);
      } else {
        actions.append(makeButton('♻️ Restaurar', () => setProfessionalStatus(professional.id, true)));
        inactiveBody.append(row);
      }
      row.append(actions);
    });
  }

  function saveScheduleSettings(event) {
    event.preventDefault();
    const nextOpening = byId('conf-abertura').value;
    const nextClosing = byId('conf-fechamento').value;
    const nextLunch = byId('conf-almoco').value;
    if (!nextOpening || !nextClosing || !nextLunch || nextOpening >= nextClosing) {
      return window.alert('Informe horários válidos.');
    }
    openingTime = nextOpening;
    closingTime = nextClosing;
    lunchTime = nextLunch;
    localStorage.setItem('lumina_abertura', openingTime);
    localStorage.setItem('lumina_fechamento', closingTime);
    localStorage.setItem('lumina_almoco', lunchTime);
    buildScheduleHours();
    renderAgenda();
    window.alert('Horários salvos neste dispositivo.');
  }

  function updateDashboard() {
    const mainAppointments = appointments.filter((item) => !item.is_continuacao);
    let revenue = 0;
    mainAppointments.forEach((appointment) => {
      const procedure = procedures.find((item) => item.id === appointment.procedimento_id)
        || procedures.find((item) => item.nome === appointment.procedimento_nome);
      revenue += Number(procedure?.valor || 0);
    });
    byId('dash-faturamento-dia').textContent = revenue.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
    byId('dash-atendimentos-dia').textContent = String(mainAppointments.length);
    byId('dash-data-ref').textContent = `Ref.: ${formatDate(selectedDate)}`;
  }

  function identifyQuestionCategory(procedureName) {
    const name = procedureName.toLocaleLowerCase('pt-BR');
    if (['botox', 'preenchimento', 'harmonização', 'bioestimulador', 'peim'].some((term) => name.includes(term))) return 'injetaveis';
    if (name.includes('endolaser')) return 'endolaser';
    if (['laser', 'cera', 'depilação'].some((term) => name.includes(term))) return 'laser';
    if (['massagem', 'drenagem'].some((term) => name.includes(term))) return 'massagem';
    if (name.includes('nutricionista')) return 'nutricao';
    if (['limpeza', 'peeling', 'microagulhamento', 'skinbooster', 'melasma', 'rosácea', 'hydragloss'].some((term) => name.includes(term))) return 'facial';
    if (['emagrecimento', 'bronze', 'velaryan'].some((term) => name.includes(term))) return 'corporal';
    return 'geral';
  }

  function buildAnamneseForm() {
    const procedureName = byId('anamnese-procedimento').value;
    const container = byId('anamnese-dinamica-container');
    container.replaceChildren();
    showElement(byId('btn-salvar-anamnese'), Boolean(procedureName));
    if (!procedureName) {
      const message = document.createElement('p');
      message.className = 'muted';
      message.textContent = 'Selecione um procedimento para carregar as perguntas.';
      container.append(message);
      return;
    }

    const title = document.createElement('h3');
    title.textContent = `Perguntas direcionadas: ${procedureName}`;
    container.append(title);
    QUESTIONS[identifyQuestionCategory(procedureName)].forEach((question, index) => {
      const block = document.createElement('div');
      block.className = 'anamnese-block';
      const questionElement = document.createElement('div');
      questionElement.className = 'anamnese-question';
      questionElement.textContent = `${index + 1}. ${question}`;
      const options = document.createElement('div');
      options.className = 'anamnese-options';
      ['Sim', 'Não'].forEach((answer) => {
        const label = document.createElement('label');
        const radio = document.createElement('input');
        radio.type = 'radio';
        radio.name = `question_${index}`;
        radio.value = answer;
        label.append(radio, ` ${answer}`);
        options.append(label);
      });
      const detail = document.createElement('input');
      detail.type = 'text';
      detail.id = `detail_${index}`;
      detail.className = 'anamnese-detail';
      detail.maxLength = 500;
      detail.placeholder = 'Detalhes (opcional)';
      block.append(questionElement, options, detail);
      container.append(block);
    });
  }

  async function saveAnamnese() {
    const patientName = byId('anamnese-paciente').value;
    const procedureName = byId('anamnese-procedimento').value;
    if (!patientName || !procedureName) {
      return setMessage('document-message', 'Selecione paciente e procedimento.', 'error');
    }
    const questions = QUESTIONS[identifyQuestionCategory(procedureName)];
    const answers = questions.map((question, index) => ({
      pergunta: question,
      resposta: document.querySelector(`input[name="question_${index}"]:checked`)?.value || 'Não respondido',
      detalhe: byId(`detail_${index}`).value.trim() || 'Sem detalhes.'
    }));
    const { error } = await db.from('anamneses').insert({
      paciente_nome: patientName,
      procedimento_nome: procedureName,
      respostas: answers
    });
    if (error) return reportError(error, 'document-message', 'Não foi possível salvar a anamnese.');
    byId('anamnese-paciente').value = '';
    byId('anamnese-procedimento').value = '';
    buildAnamneseForm();
    setMessage('document-message', 'Anamnese salva.', 'success');
    await loadAnamneses();
  }

  async function loadAnamneses() {
    const { data, error } = await db
      .from('anamneses')
      .select('id,paciente_nome,procedimento_nome,respostas,data_criacao')
      .order('data_criacao', { ascending: false });
    if (error) return reportError(error, 'document-message', 'Não foi possível carregar as anamneses.');
    anamneses = data || [];
    renderAnamneses();
  }

  function renderAnamneses() {
    const tbody = byId('tabela-anamneses');
    tbody.replaceChildren();
    if (anamneses.length === 0) tbody.append(emptyRow(4, 'Nenhuma anamnese registrada.'));
    anamneses.forEach((anamnese) => {
      const row = document.createElement('tr');
      row.append(
        createCell(formatDateTime(anamnese.data_criacao)),
        createCell(anamnese.paciente_nome),
        createCell(anamnese.procedimento_nome)
      );
      const actions = document.createElement('td');
      actions.append(makeButton('👁️ Visualizar', () => viewAnamnese(anamnese.id)));
      row.append(actions);
      tbody.append(row);
    });
  }

  function viewAnamnese(id) {
    const anamnese = anamneses.find((item) => item.id === id);
    if (!anamnese) return;
    const info = byId('view-anamnese-info');
    info.replaceChildren();
    [
      ['Paciente', anamnese.paciente_nome],
      ['Procedimento', anamnese.procedimento_nome],
      ['Data', formatDateTime(anamnese.data_criacao)]
    ].forEach(([label, value]) => {
      const line = document.createElement('p');
      const strong = document.createElement('strong');
      strong.textContent = `${label}: `;
      line.append(strong, value);
      info.append(line);
    });

    const responseContainer = byId('view-anamnese-respostas');
    responseContainer.replaceChildren();
    let answers = anamnese.respostas;
    if (typeof answers === 'string') {
      try { answers = JSON.parse(answers); } catch { answers = []; }
    }
    if (!Array.isArray(answers)) answers = [];
    answers.forEach((answer, index) => {
      const block = document.createElement('div');
      block.className = 'anamnese-block';
      const question = document.createElement('p');
      question.textContent = `${index + 1}. ${answer.pergunta || ''}`;
      question.className = 'anamnese-question';
      const response = document.createElement('p');
      response.textContent = `Resposta: ${answer.resposta || 'Não respondido'}`;
      const detail = document.createElement('p');
      detail.className = 'muted small';
      detail.textContent = `Observação: ${answer.detalhe || 'Sem detalhes.'}`;
      block.append(question, response, detail);
      responseContainer.append(block);
    });
    byId('modal-view-anamnese').classList.add('open');
  }

  initialize();
})();
